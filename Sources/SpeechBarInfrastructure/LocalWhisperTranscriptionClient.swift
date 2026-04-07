import Foundation
import SpeechBarDomain
@preconcurrency import SwiftWhisper

private func localWhisperDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [LocalWhisper] \(message)\n"
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

public enum LocalWhisperTranscriptionClientError: LocalizedError {
    case notConnected
    case missingModel(URL)
    case emptyAudio
    case emptyTranscript
    case invalidAudioEncoding(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "本地 Whisper 会话尚未准备好。"
        case .missingModel(let url):
            return "本地 Whisper 模型不存在：\(url.lastPathComponent)"
        case .emptyAudio:
            return "没有录到可用于本地转写的音频。"
        case .emptyTranscript:
            return "本地 Whisper 没有识别出有效文本。"
        case .invalidAudioEncoding(let encoding):
            return "本地 Whisper 目前只支持 16kHz 单声道 PCM，收到的是 \(encoding)。"
        }
    }
}

public actor LocalWhisperTranscriptionClient: TranscriptionClient {
    public nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation

    private var configuration: LiveTranscriptionConfiguration?
    private var audioBuffer = Data()
    private var whisper: Whisper?
    private var loadedModelURL: URL?

    public init() {
        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        self.configuration = configuration
        self.audioBuffer = Data()
        localWhisperDebugLog(
            "connect model=\(configuration.model) language=\(configuration.language) endpoint=\(configuration.endpoint.path)"
        )
        continuation.yield(.opened)
    }

    public func send(audioChunk: AudioChunk) async throws {
        guard configuration != nil else {
            throw LocalWhisperTranscriptionClientError.notConnected
        }
        audioBuffer.append(audioChunk.data)
    }

    public func finalize() async throws {
        guard let configuration else {
            throw LocalWhisperTranscriptionClientError.notConnected
        }
        guard configuration.channels == 1, configuration.encoding.lowercased() == "linear16" else {
            throw LocalWhisperTranscriptionClientError.invalidAudioEncoding(configuration.encoding)
        }
        guard !audioBuffer.isEmpty else {
            throw LocalWhisperTranscriptionClientError.emptyAudio
        }

        let modelURL = configuration.endpoint
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalWhisperTranscriptionClientError.missingModel(modelURL)
        }

        localWhisperDebugLog(
            "finalize model=\(configuration.model) bytes=\(audioBuffer.count) sampleRate=\(configuration.sampleRate) channels=\(configuration.channels)"
        )
        let whisper = try whisperInstance(for: modelURL, configuration: configuration)
        let trimmedPCM = PCMInputTrimmer.trimMonoInt16PCM(
            audioBuffer,
            sampleRate: configuration.sampleRate
        )
        let samples = decodePCM16Samples(from: trimmedPCM.data)
        localWhisperDebugLog(
            "decoded pcm samples=\(samples.count), leadingSamplesTrimmed=\(trimmedPCM.leadingSamplesTrimmed), trailingSamplesTrimmed=\(trimmedPCM.trailingSamplesTrimmed)"
        )
        localWhisperDebugLog("starting whisper transcribe")
        do {
            let segments = try await whisper.transcribe(audioFrames: samples)
            localWhisperDebugLog("transcribe completed segments=\(segments.count)")
            let transcript = segments
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTranscript = Self.normalizeTranscriptForInput(transcript)

            if !normalizedTranscript.isEmpty {
                if normalizedTranscript != transcript {
                    localWhisperDebugLog("collapsed repetitive transcript to='\(normalizedTranscript)'")
                }
                localWhisperDebugLog("parsed transcript='\(normalizedTranscript)'")
                continuation.yield(.final(normalizedTranscript))
            } else {
                localWhisperDebugLog("parsed transcript is empty")
                throw LocalWhisperTranscriptionClientError.emptyTranscript
            }
        } catch {
            localWhisperDebugLog("transcribe failed error=\(String(describing: error))")
            throw error
        }
        continuation.yield(.closed)
    }

    public func close() async {
        audioBuffer = Data()
        configuration = nil
    }

    private func whisperInstance(
        for modelURL: URL,
        configuration: LiveTranscriptionConfiguration
    ) throws -> Whisper {
        if let whisper, loadedModelURL == modelURL {
            return whisper
        }

        let params = WhisperParams(strategy: .greedy)
        params.language = whisperLanguage(for: configuration.language)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = true
        params.max_len = 80
        params.max_tokens = 96
        params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 1)))

        localWhisperDebugLog(
            "loading whisper model path=\(modelURL.path) language=\(params.language.rawValue) threads=\(params.n_threads) singleSegment=\(params.single_segment) maxLen=\(params.max_len) maxTokens=\(params.max_tokens)"
        )
        let whisper = Whisper(fromFileURL: modelURL, withParams: params)
        self.whisper = whisper
        self.loadedModelURL = modelURL
        return whisper
    }

    private func whisperLanguage(for value: String) -> WhisperLanguage {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty || normalized == "auto" {
            return .auto
        }

        let baseLanguage = normalized
            .split(separator: "-")
            .first
            .map(String.init) ?? normalized

        return WhisperLanguage(rawValue: baseLanguage) ?? .auto
    }

    private func decodePCM16Samples(from data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return int16Buffer.map { sample in
                max(-1, min(1, Float(sample) / Float(Int16.max)))
            }
        }
    }

    static func normalizeTranscriptForInput(_ transcript: String) -> String {
        let trimmed = transcript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else { return trimmed }

        let maxCandidateLength = min(trimmed.count / 2 + 4, 80)
        guard maxCandidateLength >= 6 else { return trimmed }

        for candidateLength in stride(from: maxCandidateLength, through: 6, by: -1) {
            let rawCandidate = String(trimmed.prefix(candidateLength))
            let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate.count >= 6 else { continue }
            guard let remainderStart = trimmed.index(trimmed.startIndex, offsetBy: rawCandidate.count, limitedBy: trimmed.endIndex) else {
                continue
            }

            if normalizeRepeatedRemainder(
                String(trimmed[remainderStart...]),
                candidate: candidate
            ) != nil {
                return candidate
            }
        }

        return trimmed
    }

    private static func normalizeRepeatedRemainder(
        _ remainder: String,
        candidate: String
    ) -> String? {
        var remaining = remainder
        var repeats = 0

        while true {
            remaining = remaining.trimmingCharacters(in: repetitionBoundaryCharacters)
            if remaining.isEmpty { break }

            if remaining.hasPrefix(candidate) {
                remaining.removeFirst(candidate.count)
                repeats += 1
                continue
            }

            var matchedShortenedCandidate = false
            let maxDroppedPrefix = min(3, max(1, candidate.count / 8))
            for droppedPrefixLength in 1...maxDroppedPrefix {
                let shortenedCandidate = String(candidate.dropFirst(droppedPrefixLength))
                guard !shortenedCandidate.isEmpty else { continue }
                if remaining.hasPrefix(shortenedCandidate) {
                    remaining.removeFirst(shortenedCandidate.count)
                    repeats += 1
                    matchedShortenedCandidate = true
                    break
                }
            }

            if !matchedShortenedCandidate {
                break
            }
        }

        guard repeats >= 1 else { return nil }
        remaining = remaining.trimmingCharacters(in: repetitionBoundaryCharacters)
        if remaining.isEmpty || candidate.hasPrefix(remaining) {
            return candidate
        }
        return nil
    }

    private static let repetitionBoundaryCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
}
