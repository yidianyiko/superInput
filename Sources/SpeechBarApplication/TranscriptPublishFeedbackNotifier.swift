import Foundation
import SpeechBarDomain

public struct TranscriptPublishFeedbackStart: Sendable, Equatable, Identifiable {
    public let publishID: UUID
    public let transcript: PublishedTranscript
    public let createdAt: Date

    public var id: UUID { publishID }

    public init(
        publishID: UUID,
        transcript: PublishedTranscript,
        createdAt: Date = Date()
    ) {
        self.publishID = publishID
        self.transcript = transcript
        self.createdAt = createdAt
    }
}

public struct TranscriptPublishFeedbackCompletion: Sendable, Equatable, Identifiable {
    public let publishID: UUID
    public let outcome: TranscriptDeliveryOutcome
    public let createdAt: Date

    public var id: UUID { publishID }

    public init(
        publishID: UUID,
        outcome: TranscriptDeliveryOutcome,
        createdAt: Date = Date()
    ) {
        self.publishID = publishID
        self.outcome = outcome
        self.createdAt = createdAt
    }
}

public struct TranscriptPublishFeedbackFailure: Sendable, Equatable, Identifiable {
    public let publishID: UUID
    public let createdAt: Date

    public var id: UUID { publishID }

    public init(
        publishID: UUID,
        createdAt: Date = Date()
    ) {
        self.publishID = publishID
        self.createdAt = createdAt
    }
}

public enum TranscriptPublishFeedbackEvent: Sendable, Equatable {
    case started(TranscriptPublishFeedbackStart)
    case completed(TranscriptPublishFeedbackCompletion)
    case failed(TranscriptPublishFeedbackFailure)
}

public final class TranscriptPublishFeedbackNotifier: Sendable {
    public let events: AsyncStream<TranscriptPublishFeedbackEvent>

    private let continuation: AsyncStream<TranscriptPublishFeedbackEvent>.Continuation

    public init() {
        var capturedContinuation: AsyncStream<TranscriptPublishFeedbackEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func notify(_ event: TranscriptPublishFeedbackEvent) {
        continuation.yield(event)
    }
}
