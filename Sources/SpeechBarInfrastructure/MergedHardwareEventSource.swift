import Foundation
import SpeechBarDomain

public final class MergedHardwareEventSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private var relayTasks: [Task<Void, Never>] = []

    public init(sources: [any HardwareEventSource]) {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        for source in sources {
            let task = Task { [continuation] in
                for await event in source.events {
                    continuation.yield(event)
                }
            }
            relayTasks.append(task)
        }
    }

    deinit {
        relayTasks.forEach { $0.cancel() }
        continuation.finish()
    }
}
