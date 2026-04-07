import Foundation
import SpeechBarDomain

public struct ReplayRunResult: Sendable, Equatable {
    public var eventCount: Int
    public var runtimeSnapshotCount: Int
    public var rebuiltBoardSnapshot: TaskBoardSnapshot

    public init(
        eventCount: Int,
        runtimeSnapshotCount: Int,
        rebuiltBoardSnapshot: TaskBoardSnapshot
    ) {
        self.eventCount = eventCount
        self.runtimeSnapshotCount = runtimeSnapshotCount
        self.rebuiltBoardSnapshot = rebuiltBoardSnapshot
    }
}

public struct ReplayRunner {
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func loadEvents(from bundle: ReplayBundle) throws -> [AgentObservationEvent] {
        let data = try Data(contentsOf: bundle.rawEventsFile)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.map { line in
            try decoder.decode(AgentObservationEvent.self, from: Data(line.utf8))
        }
    }

    public func rebuild(
        from bundle: ReplayBundle,
        reducer: any AgentStateReducing,
        snapshotBuilder: any TaskBoardSnapshotBuilding
    ) throws -> ReplayRunResult {
        let events = try loadEvents(from: bundle)
        var runtimeSnapshots: [String: AgentRuntimeSnapshot] = [:]
        for event in events {
            let key = "\(event.provider.rawValue):\(event.sessionID)"
            let reduction = reducer.reduce(event: event, current: runtimeSnapshots[key])
            runtimeSnapshots[key] = reduction.snapshot
        }

        let board = snapshotBuilder.makeSnapshot(
            from: Array(runtimeSnapshots.values),
            selection: TaskBoardSelectionState(),
            generatedAt: Date()
        )
        return ReplayRunResult(
            eventCount: events.count,
            runtimeSnapshotCount: runtimeSnapshots.count,
            rebuiltBoardSnapshot: board
        )
    }
}
