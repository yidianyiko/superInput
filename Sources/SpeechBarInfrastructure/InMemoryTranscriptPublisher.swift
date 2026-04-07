import Foundation
import SpeechBarDomain

public actor InMemoryTranscriptPublisher: TranscriptPublisher {
    private var storedTranscripts: [PublishedTranscript] = []

    public init() {}

    public func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome {
        storedTranscripts.append(transcript)
        return .publishedOnly
    }

    public func transcripts() -> [PublishedTranscript] {
        storedTranscripts
    }
}
