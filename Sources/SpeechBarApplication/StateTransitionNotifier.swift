import Foundation
import SpeechBarDomain

public struct StateTransitionNotification: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sessionID: String
    public let provider: AgentProvider
    public let from: BoardState?
    public let to: BoardState
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        provider: AgentProvider,
        from: BoardState?,
        to: BoardState,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.provider = provider
        self.from = from
        self.to = to
        self.createdAt = createdAt
    }
}

public final class StateTransitionNotifier: @unchecked Sendable {
    public let events: AsyncStream<StateTransitionNotification>

    private let continuation: AsyncStream<StateTransitionNotification>.Continuation

    public init() {
        var capturedContinuation: AsyncStream<StateTransitionNotification>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    public func notify(_ notification: StateTransitionNotification) {
        continuation.yield(notification)
    }
}
