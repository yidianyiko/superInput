import Foundation
import SpeechBarDomain

private func openAIWhisperDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Whisper] \(message)\n"
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

public enum OpenAIWhisperTranscriptionClientError: LocalizedError {
    case notConnected
    case emptyAudio
    case invalidResponse
    case badHTTPStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "OpenAI Whisper upload session was not prepared correctly."
        case .emptyAudio:
            return "No audio was recorded."
        case .invalidResponse:
            return "OpenAI Whisper returned an unexpected response."
        case .badHTTPStatus(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "OpenAI Whisper request failed with HTTP \(code)."
            }
            return "OpenAI Whisper request failed with HTTP \(code): \(trimmed)"
        }
    }
}

public actor OpenAIWhisperTranscriptionClient: TranscriptionClient {
    public nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let session: URLSession

    private var apiKey: String?
    private var configuration: LiveTranscriptionConfiguration?
    private var audioBuffer = Data()

    public init(session: URLSession = .shared) {
        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
        self.session = session
    }

    public func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        self.apiKey = apiKey
        self.configuration = configuration
        self.audioBuffer = Data()
        continuation.yield(.opened)
    }

    public func send(audioChunk: AudioChunk) async throws {
        guard configuration != nil, apiKey != nil else {
            throw OpenAIWhisperTranscriptionClientError.notConnected
        }
        audioBuffer.append(audioChunk.data)
        if audioBuffer.count % 32000 < audioChunk.data.count {
            openAIWhisperDebugLog("audio buffer growing: \(audioBuffer.count) bytes")
        }
    }

    public func finalize() async throws {
        guard let apiKey, let configuration else {
            throw OpenAIWhisperTranscriptionClientError.notConnected
        }
        guard !audioBuffer.isEmpty else {
            throw OpenAIWhisperTranscriptionClientError.emptyAudio
        }

        let trimmedPCM = PCMInputTrimmer.trimMonoInt16PCM(
            audioBuffer,
            sampleRate: configuration.sampleRate
        )
        let wavData = makeWAV(
            from: trimmedPCM.data,
            sampleRate: configuration.sampleRate,
            channels: configuration.channels
        )

        let requestURL = transcriptionURL(from: configuration.endpoint)
        openAIWhisperDebugLog(
            "sending WAV (\(wavData.count) bytes) to \(requestURL.absoluteString), trimmed leadingSamples=\(trimmedPCM.leadingSamplesTrimmed), trailingSamples=\(trimmedPCM.trailingSamplesTrimmed)"
        )

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(boundary: boundary, wavData: wavData, configuration: configuration)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIWhisperTranscriptionClientError.invalidResponse
        }

        openAIWhisperDebugLog("OpenAI Whisper HTTP \(httpResponse.statusCode), response size = \(data.count) bytes")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            openAIWhisperDebugLog("OpenAI Whisper error body: \(body)")
            throw OpenAIWhisperTranscriptionClientError.badHTTPStatus(httpResponse.statusCode, body)
        }

        let transcript = try parseTranscript(from: data)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        openAIWhisperDebugLog("parsed transcript = '\(trimmed)'")
        if !trimmed.isEmpty {
            continuation.yield(.final(trimmed))
        }
        continuation.yield(.closed)
    }

    public func close() async {
        audioBuffer = Data()
        apiKey = nil
        configuration = nil
    }

    private func transcriptionURL(from endpoint: URL) -> URL {
        let path = endpoint.path.lowercased()
        if path.hasSuffix("/audio/transcriptions") {
            return endpoint
        }

        var normalized = endpoint
        if path.hasSuffix("/v1") {
            normalized.append(path: "audio/transcriptions")
            return normalized
        }

        if path.isEmpty || path == "/" {
            normalized.append(path: "v1")
            normalized.append(path: "audio/transcriptions")
            return normalized
        }

        normalized.append(path: "audio/transcriptions")
        return normalized
    }

    private func makeMultipartBody(
        boundary: String,
        wavData: Data,
        configuration: LiveTranscriptionConfiguration
    ) -> Data {
        var data = Data()

        appendFormField(named: "model", value: configuration.model, to: &data, boundary: boundary)

        let trimmedLanguage = configuration.language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLanguage.isEmpty {
            appendFormField(named: "language", value: trimmedLanguage, to: &data, boundary: boundary)
        }

        appendFormField(named: "response_format", value: "json", to: &data, boundary: boundary)

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"speechbar.wav\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        data.append(wavData)
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return data
    }

    private func appendFormField(named name: String, value: String, to data: inout Data, boundary: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func parseTranscript(from data: Data) throws -> String {
        let envelope = try JSONDecoder().decode(OpenAIWhisperTranscriptionEnvelope.self, from: data)
        return envelope.text
    }

    private func makeWAV(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample = 16
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let subchunk2Size = UInt32(pcmData.count)
        let chunkSize = 36 + subchunk2Size

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndianBytes(chunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(littleEndianBytes(UInt32(16)))
        data.append(littleEndianBytes(UInt16(1)))
        data.append(littleEndianBytes(UInt16(channels)))
        data.append(littleEndianBytes(UInt32(sampleRate)))
        data.append(littleEndianBytes(byteRate))
        data.append(littleEndianBytes(blockAlign))
        data.append(littleEndianBytes(UInt16(bitsPerSample)))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndianBytes(subchunk2Size))
        data.append(pcmData)
        return data
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndianValue = value.littleEndian
        return Data(bytes: &littleEndianValue, count: MemoryLayout<T>.size)
    }
}

private struct OpenAIWhisperTranscriptionEnvelope: Decodable {
    let text: String
}
