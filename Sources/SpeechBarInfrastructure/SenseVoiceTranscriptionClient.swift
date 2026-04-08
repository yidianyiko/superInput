import Foundation
import SpeechBarDomain

private func senseVoiceDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [SenseVoice] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

public enum SenseVoiceTranscriptionClientError: LocalizedError {
    case notConnected
    case missingModel(URL)
    case missingTokens(URL)
    case missingRuntime(URL)
    case missingExecutable(URL)
    case emptyAudio
    case emptyTranscript
    case invalidAudioEncoding(String)
    case executableFailed(String)
    case timedOut
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "SenseVoice 会话尚未准备好。"
        case .missingModel(let url):
            return "SenseVoice 模型文件不存在：\(url.lastPathComponent)"
        case .missingTokens(let url):
            return "SenseVoice tokens 文件不存在：\(url.lastPathComponent)"
        case .missingRuntime(let url):
            return "SenseVoice 运行时不存在：\(url.path)"
        case .missingExecutable(let url):
            return "SenseVoice 可执行文件不存在：\(url.path)"
        case .emptyAudio:
            return "没有录到可用于 SenseVoice 转写的音频。"
        case .emptyTranscript:
            return "SenseVoice 没有识别出有效文本。"
        case .invalidAudioEncoding(let encoding):
            return "SenseVoice 目前只支持 16kHz 单声道 PCM，收到的是 \(encoding)。"
        case .executableFailed(let message):
            return "SenseVoice 推理失败：\(message)"
        case .timedOut:
            return "SenseVoice 推理超时。"
        case .invalidResponse:
            return "SenseVoice 返回了无法解析的结果。"
        }
    }
}

public actor SenseVoiceTranscriptionClient: TranscriptionClient {
    public nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let modelStore: SenseVoiceModelStore
    private let fileManager: FileManager
    private let processTimeout: Duration

    private var configuration: LiveTranscriptionConfiguration?
    private var audioBuffer = Data()

    public init(
        modelStore: SenseVoiceModelStore,
        fileManager: FileManager = .default,
        processTimeout: Duration = .seconds(8)
    ) {
        self.modelStore = modelStore
        self.fileManager = fileManager
        self.processTimeout = processTimeout

        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        self.configuration = configuration
        self.audioBuffer = Data()
        senseVoiceDebugLog(
            "connect model=\(configuration.model) language=\(configuration.language) endpoint=\(configuration.endpoint.path)"
        )
        continuation.yield(.opened)
    }

    public func send(audioChunk: AudioChunk) async throws {
        guard configuration != nil else {
            throw SenseVoiceTranscriptionClientError.notConnected
        }
        audioBuffer.append(audioChunk.data)
    }

    public func finalize() async throws {
        guard let configuration else {
            throw SenseVoiceTranscriptionClientError.notConnected
        }
        guard configuration.channels == 1, configuration.encoding.lowercased() == "linear16" else {
            throw SenseVoiceTranscriptionClientError.invalidAudioEncoding(configuration.encoding)
        }
        guard !audioBuffer.isEmpty else {
            throw SenseVoiceTranscriptionClientError.emptyAudio
        }

        let modelDirectory = configuration.endpoint
        let modelURL = modelFileURL(in: modelDirectory) ?? modelDirectory.appendingPathComponent("model.int8.onnx")
        let tokensURL = modelDirectory.appendingPathComponent("tokens.txt")
        let executableURL = await MainActor.run {
            modelStore.resolvedOfflineExecutableURL()
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw SenseVoiceTranscriptionClientError.missingModel(modelURL)
        }
        guard fileManager.fileExists(atPath: tokensURL.path) else {
            throw SenseVoiceTranscriptionClientError.missingTokens(tokensURL)
        }
        guard let executableURL else {
            throw SenseVoiceTranscriptionClientError.missingRuntime(
                await MainActor.run { modelStore.runtimeDirectory }
            )
        }
        guard fileManager.fileExists(atPath: executableURL.path) else {
            throw SenseVoiceTranscriptionClientError.missingExecutable(executableURL)
        }

        let trimStartedAt = Date()
        let trimmedPCM = PCMInputTrimmer.trimMonoInt16PCM(
            audioBuffer,
            sampleRate: configuration.sampleRate,
            amplitudeThreshold: 28,
            leadingPaddingMilliseconds: 720,
            trailingPaddingMilliseconds: 240,
            minimumLeadingRetainedMilliseconds: 600,
            prependLeadingSilenceMilliseconds: 120
        )
        guard !trimmedPCM.data.isEmpty else {
            throw SenseVoiceTranscriptionClientError.emptyAudio
        }
        senseVoiceDebugLog(
            "trimmed pcm bytes=\(trimmedPCM.data.count) leadingSamplesTrimmed=\(trimmedPCM.leadingSamplesTrimmed) trailingSamplesTrimmed=\(trimmedPCM.trailingSamplesTrimmed) trimLatency=\(String(format: "%.3f", Date().timeIntervalSince(trimStartedAt)))s"
        )

        let inputURL = fileManager.temporaryDirectory
            .appendingPathComponent("sensevoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? fileManager.removeItem(at: inputURL) }

        let wavWriteStartedAt = Date()
        try PCM16WAVFileWriter.writeMonoWAV(
            pcm16Data: trimmedPCM.data,
            sampleRate: configuration.sampleRate,
            to: inputURL
        )
        senseVoiceDebugLog(
            "wav prepared path=\(inputURL.lastPathComponent) bytes=\(trimmedPCM.data.count) writeLatency=\(String(format: "%.3f", Date().timeIntervalSince(wavWriteStartedAt)))s"
        )

        senseVoiceDebugLog(
            "finalize model=\(configuration.model) bytes=\(trimmedPCM.data.count) sampleRate=\(configuration.sampleRate) language=\(configuration.language)"
        )

        let executionProviders = preferredExecutionProviders()
        var lastError: Error?

        for provider in executionProviders {
            do {
                let executionStartedAt = Date()
                let transcript = try await runExecutable(
                    executableURL: executableURL,
                    inputURL: inputURL,
                    modelURL: modelURL,
                    tokensURL: tokensURL,
                    language: configuration.language,
                    provider: provider
                )
                let normalized = Self.normalizeTranscriptForInput(transcript)
                guard !normalized.isEmpty else {
                    throw SenseVoiceTranscriptionClientError.emptyTranscript
                }
                senseVoiceDebugLog(
                    "parsed transcript='\(normalized)' provider=\(provider) executionLatency=\(String(format: "%.3f", Date().timeIntervalSince(executionStartedAt)))s"
                )
                continuation.yield(.final(normalized))
                continuation.yield(.closed)
                return
            } catch {
                lastError = error
                senseVoiceDebugLog("provider=\(provider) failed error=\(String(describing: error))")
            }
        }

        throw lastError ?? SenseVoiceTranscriptionClientError.emptyTranscript
    }

    public func close() async {
        audioBuffer = Data()
        configuration = nil
    }

    private func runExecutable(
        executableURL: URL,
        inputURL: URL,
        modelURL: URL,
        tokensURL: URL,
        language: String,
        provider: String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try Self.executeOfflineRecognizer(
                    executableURL: executableURL,
                    inputURL: inputURL,
                    modelURL: modelURL,
                    tokensURL: tokensURL,
                    language: language,
                    provider: provider
                )
            }
            group.addTask {
                try await Task.sleep(for: self.processTimeout)
                throw SenseVoiceTranscriptionClientError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func executeOfflineRecognizer(
        executableURL: URL,
        inputURL: URL,
        modelURL: URL,
        tokensURL: URL,
        language: String,
        provider: String
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--print-args=false",
            "--sense-voice-model=\(modelURL.path)",
            "--tokens=\(tokensURL.path)",
            "--sense-voice-language=\(normalizedSenseVoiceLanguage(language))",
            "--provider=\(provider)",
            "--num-threads=\(recommendedThreadCount())",
            inputURL.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let combined = [stdout, stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SenseVoiceTranscriptionClientError.executableFailed(trimmed.isEmpty ? "unknown error" : trimmed)
        }

        let lines = combined
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let jsonLine = lines.last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }) else {
            throw SenseVoiceTranscriptionClientError.invalidResponse
        }

        guard let data = jsonLine.data(using: .utf8) else {
            throw SenseVoiceTranscriptionClientError.invalidResponse
        }
        let envelope = try JSONDecoder().decode(SenseVoiceOfflineEnvelope.self, from: data)
        return envelope.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modelFileURL(in directory: URL) -> URL? {
        let preferred = directory.appendingPathComponent("model.int8.onnx")
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return fileURLs
            .filter {
                let filename = $0.lastPathComponent.lowercased()
                return filename.hasSuffix(".onnx") && filename.contains("model")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private func preferredExecutionProviders() -> [String] {
        let preferred = normalizedExecutionProvider(modelStore.defaultModel.preferredExecutionProvider)
        let fallback = preferred == "cpu" ? "coreml" : "cpu"
        return [preferred, fallback]
    }

    private static func recommendedThreadCount() -> Int {
        max(1, min(4, ProcessInfo.processInfo.processorCount - 1))
    }

    private func normalizedExecutionProvider(_ provider: String) -> String {
        let normalized = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "coreml":
            return "coreml"
        default:
            return "cpu"
        }
    }

    private static func normalizedSenseVoiceLanguage(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty || normalized == "auto" {
            return "auto"
        }

        let baseLanguage = normalized
            .split(separator: "-")
            .first
            .map(String.init) ?? normalized

        switch baseLanguage {
        case "zh", "en", "ja", "ko", "yue":
            return baseLanguage
        default:
            return "auto"
        }
    }

    static func normalizeTranscriptForInput(_ transcript: String) -> String {
        transcript
            .replacingOccurrences(
                of: #"<\|[^|]+?\|>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SenseVoiceOfflineEnvelope: Decodable {
    let text: String
}
