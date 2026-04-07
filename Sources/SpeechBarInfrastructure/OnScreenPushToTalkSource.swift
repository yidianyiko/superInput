import Foundation
import SpeechBarDomain

public final class OnScreenPushToTalkSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>
    private let continuation: AsyncStream<HardwareEvent>.Continuation

    public init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    @MainActor
    public func sendPressed() {
        continuation.yield(
            HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed)
        )
    }

    @MainActor
    public func sendReleased() {
        continuation.yield(
            HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased)
        )
    }
}
