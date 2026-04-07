import Foundation
import Testing
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("LocalWhisperTranscriptionClientIntegration")
struct LocalWhisperTranscriptionClientIntegrationTests {
    @Test
    func transcribesInstalledLargeV3TurboModelWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["STARTUP_RUN_LOCAL_WHISPER_INTEGRATION"] == "1" else {
            return
        }

        let defaultModelPath = NSString(string: "~/Library/Application Support/SlashVibe/Models/Whisper/ggml-large-v3-turbo-q5_0.bin")
            .expandingTildeInPath
        let defaultSamplePath = "/tmp/speechbar_last_recording.wav"

        let modelURL = URL(fileURLWithPath: environment["STARTUP_LOCAL_WHISPER_MODEL_PATH"] ?? defaultModelPath)
        let sampleURL = URL(fileURLWithPath: environment["STARTUP_LOCAL_WHISPER_SAMPLE_PATH"] ?? defaultSamplePath)

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            Issue.record("Local whisper model not found at \(modelURL.path)")
            return
        }
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            Issue.record("Sample WAV not found at \(sampleURL.path)")
            return
        }

        let wavData = try Data(contentsOf: sampleURL)
        let sample = try decodePCM16WAV(from: wavData)

        let client = LocalWhisperTranscriptionClient()
        let eventsTask = Task<[TranscriptEvent], Never> {
            var events: [TranscriptEvent] = []
            for await event in client.events {
                events.append(event)
                if event == .closed {
                    break
                }
            }
            return events
        }

        let configuration = LiveTranscriptionConfiguration(
            endpoint: modelURL,
            model: "ggml-large-v3-turbo-q5_0",
            language: "zh",
            encoding: "linear16",
            sampleRate: sample.sampleRate,
            channels: sample.channels,
            interimResults: false,
            punctuate: true,
            smartFormat: true,
            vadEvents: false,
            endpointingMilliseconds: 0,
            utteranceEndMilliseconds: 0,
            keywords: []
        )

        try await client.connect(apiKey: "local-whisper-model", configuration: configuration)
        try await client.send(audioChunk: AudioChunk(
            data: sample.pcmData,
            format: .deepgramLinear16,
            sequenceNumber: 0
        ))
        try await client.finalize()

        let events = await eventsTask.value
        #expect(events.contains(.opened))
        #expect(events.contains(.closed))
    }

    private func decodePCM16WAV(from data: Data) throws -> WAVSample {
        guard data.count > 44 else {
            throw WAVParseError.invalidFile
        }
        guard String(data: data.prefix(4), encoding: .ascii) == "RIFF" else {
            throw WAVParseError.invalidFile
        }
        guard String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw WAVParseError.invalidFile
        }

        var offset = 12
        var sampleRate = 16_000
        var channels = 1
        var pcmData: Data?

        while offset + 8 <= data.count {
            let chunkIDData = data[offset..<(offset + 4)]
            let chunkID = String(data: chunkIDData, encoding: .ascii) ?? ""
            let chunkSize = Int(littleEndianUInt32(from: data[(offset + 4)..<(offset + 8)]))
            let chunkDataStart = offset + 8
            let chunkDataEnd = chunkDataStart + chunkSize
            guard chunkDataEnd <= data.count else {
                throw WAVParseError.invalidFile
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw WAVParseError.invalidFormat
                }
                channels = Int(littleEndianUInt16(from: data[(chunkDataStart + 2)..<(chunkDataStart + 4)]))
                sampleRate = Int(littleEndianUInt32(from: data[(chunkDataStart + 4)..<(chunkDataStart + 8)]))
                let bitsPerSample = Int(littleEndianUInt16(from: data[(chunkDataStart + 14)..<(chunkDataStart + 16)]))
                guard bitsPerSample == 16 else {
                    throw WAVParseError.unsupportedBitsPerSample(bitsPerSample)
                }
            } else if chunkID == "data" {
                pcmData = Data(data[chunkDataStart..<chunkDataEnd])
                break
            }

            offset = chunkDataEnd + (chunkSize % 2)
        }

        guard let pcmData else {
            throw WAVParseError.missingPCMData
        }

        return WAVSample(sampleRate: sampleRate, channels: channels, pcmData: pcmData)
    }

    private func littleEndianUInt16(from data: Data.SubSequence) -> UInt16 {
        data.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt16.self).littleEndian
        }
    }

    private func littleEndianUInt32(from data: Data.SubSequence) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).littleEndian
        }
    }
}

private struct WAVSample {
    let sampleRate: Int
    let channels: Int
    let pcmData: Data
}

private enum WAVParseError: LocalizedError {
    case invalidFile
    case invalidFormat
    case unsupportedBitsPerSample(Int)
    case missingPCMData

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "WAV file is invalid."
        case .invalidFormat:
            "WAV format chunk is invalid."
        case .unsupportedBitsPerSample(let value):
            "Only 16-bit PCM WAV is supported, got \(value)."
        case .missingPCMData:
            "WAV file is missing PCM data."
        }
    }
}
