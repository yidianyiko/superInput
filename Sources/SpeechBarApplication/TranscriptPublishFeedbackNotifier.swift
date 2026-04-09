import Foundation
import SpeechBarDomain

public struct TranscriptPublishFeedbackStart: Sendable, Equatable, Identifiable {
    public let publishID: UUID
    public let transcript: PublishedTranscript?
    public let createdAt: Date

    public var id: UUID { publishID }

    public init(
        publishID: UUID,
        transcript: PublishedTranscript? = nil,
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

public final class TranscriptPublishFeedbackNotifier: @unchecked Sendable {
    public var events: AsyncStream<TranscriptPublishFeedbackEvent> {
        let subscriberID = UUID()

        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            storeContinuation(continuation, for: subscriberID)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(for: subscriberID)
            }
        }
    }

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<TranscriptPublishFeedbackEvent>.Continuation] = [:]

    public init() {}

    public func notify(_ event: TranscriptPublishFeedbackEvent) {
        let continuations = activeContinuations()
        for continuation in continuations {
            continuation.yield(event)
        }
    }

    private func storeContinuation(
        _ continuation: AsyncStream<TranscriptPublishFeedbackEvent>.Continuation,
        for subscriberID: UUID
    ) {
        lock.lock()
        continuations[subscriberID] = continuation
        lock.unlock()
    }

    private func removeContinuation(for subscriberID: UUID) {
        lock.lock()
        continuations.removeValue(forKey: subscriberID)
        lock.unlock()
    }

    private func activeContinuations() -> [AsyncStream<TranscriptPublishFeedbackEvent>.Continuation] {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        return active
    }
}
