import Foundation
import os.log
import SpeechBarDomain

private let logger = Logger(subsystem: "com.startup.speechbar", category: "Deepgram")

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Deepgram] \(message)\n"
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

public enum DeepgramPrerecordedClientError: LocalizedError {
    case notConnected
    case emptyAudio
    case badHTTPStatus(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Deepgram upload session was not prepared correctly."
        case .emptyAudio:
            return "No audio was recorded."
        case .badHTTPStatus(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Deepgram request failed with HTTP \(code)."
            }
            return "Deepgram request failed with HTTP \(code): \(trimmed)"
        case .invalidResponse:
            return "Deepgram returned an unexpected response."
        }
    }
}

public actor DeepgramPrerecordedClient: TranscriptionClient {
    public nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let session: URLSession
    private let formatter = TranscriptFormatter()

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
            throw DeepgramPrerecordedClientError.notConnected
        }
        audioBuffer.append(audioChunk.data)
        if audioBuffer.count % 32000 < audioChunk.data.count {
            debugLog("audio buffer growing: \(audioBuffer.count) bytes")
        }
    }

    public func finalize() async throws {
        guard let apiKey, let configuration else {
            throw DeepgramPrerecordedClientError.notConnected
        }
        guard !audioBuffer.isEmpty else {
            debugLog("audioBuffer is empty, no audio recorded")
            throw DeepgramPrerecordedClientError.emptyAudio
        }

        let trimmedPCM = PCMInputTrimmer.trimMonoInt16PCM(
            audioBuffer,
            sampleRate: configuration.sampleRate
        )
        let pcmData = trimmedPCM.data

        debugLog(
            "audioBuffer size = \(audioBuffer.count) bytes, trimmed = \(pcmData.count) bytes, leadingSamplesTrimmed = \(trimmedPCM.leadingSamplesTrimmed), trailingSamplesTrimmed = \(trimmedPCM.trailingSamplesTrimmed)"
        )

        let wavData = makeWAV(
            from: pcmData,
            sampleRate: configuration.sampleRate,
            channels: configuration.channels
        )

        debugLog("sending WAV (\(wavData.count) bytes) to Deepgram prerecorded API")
        debugLog("URL: \(configuration.prerecordedURL.absoluteString)")

        // Save WAV for debugging
        let debugPath = "/tmp/speechbar_last_recording.wav"
        try? wavData.write(to: URL(fileURLWithPath: debugPath))
        debugLog("saved WAV to \(debugPath)")

        var request = URLRequest(url: configuration.prerecordedURL)
        request.httpMethod = "POST"
        request.httpBody = wavData
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramPrerecordedClientError.invalidResponse
        }

        debugLog("Deepgram HTTP \(httpResponse.statusCode), response size = \(data.count) bytes")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog("Deepgram error body: \(body)")
            throw DeepgramPrerecordedClientError.badHTTPStatus(httpResponse.statusCode, body)
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        debugLog("Deepgram response: \(responseBody)")

        let transcript = try parseTranscript(from: data)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("parsed transcript = '\(trimmed)'")
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

    private func parseTranscript(from data: Data) throws -> String {
        let envelope = try JSONDecoder().decode(PrerecordedEnvelope.self, from: data)
        guard
            let channel = envelope.results.channels.first,
            let alternative = channel.alternatives.first
        else {
            throw DeepgramPrerecordedClientError.invalidResponse
        }
        return formatter.format(
            transcript: alternative.transcript,
            words: alternative.words ?? []
        )
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

private struct PrerecordedEnvelope: Decodable {
    let results: Results
}

private struct Results: Decodable {
    let channels: [ResultChannel]
}

private struct ResultChannel: Decodable {
    let alternatives: [ResultAlternative]
}

private struct ResultAlternative: Decodable {
    let transcript: String?
    let words: [DeepgramWord]?
}
