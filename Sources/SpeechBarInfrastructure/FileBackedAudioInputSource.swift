import Foundation
import SpeechBarDomain

public final class FileBackedAudioInputSource: AudioInputSource, @unchecked Sendable {
    public let audioLevels: AsyncStream<AudioLevelSample>

    private let fileURL: URL
    private let chunkSize: Int
    private let format: AudioEncodingDescriptor
    private var captureTask: Task<Void, Never>?

    public init(
        fileURL: URL,
        chunkSize: Int = 1_024,
        format: AudioEncodingDescriptor = .deepgramLinear16
    ) {
        self.audioLevels = AsyncStream { _ in }
        self.fileURL = fileURL
        self.chunkSize = chunkSize
        self.format = format
    }

    public func requestRecordPermission() async -> AudioInputPermissionStatus {
        .granted
    }

    public func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        let data = try Data(contentsOf: fileURL)

        return AsyncThrowingStream { continuation in
            self.captureTask?.cancel()
            self.captureTask = Task {
                var offset = 0
                var sequenceNumber: Int64 = 0

                while offset < data.count, !Task.isCancelled {
                    let end = min(offset + self.chunkSize, data.count)
                    let chunk = data[offset..<end]
                    continuation.yield(
                        AudioChunk(
                            data: Data(chunk),
                            format: self.format,
                            sequenceNumber: sequenceNumber
                        )
                    )
                    sequenceNumber += 1
                    offset = end
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                self.captureTask?.cancel()
            }
        }
    }

    public func stopCapture() async {
        captureTask?.cancel()
        captureTask = nil
    }
}
