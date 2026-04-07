import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarInfrastructure

@Suite("FileBackedAudioInputSource")
struct FileBackedAudioInputSourceTests {
    @Test
    func fileBackedAudioInputSourceStreamsPCMChunks() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let fileURL = temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pcm")
        let originalData = Data((0..<255).map { UInt8($0) }) + Data((0..<80).map { UInt8($0) })
        try originalData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let source = FileBackedAudioInputSource(fileURL: fileURL, chunkSize: 64)
        #expect(await source.requestRecordPermission() == .granted)

        let stream = try await source.startCapture()
        var collected = Data()
        var chunkCount = 0

        for try await chunk in stream {
            chunkCount += 1
            #expect(chunk.format == .deepgramLinear16)
            collected.append(chunk.data)
        }

        #expect(chunkCount > 1)
        #expect(collected == originalData)
    }
}
