import Foundation
import SpeechBarDomain

public struct DefaultAgentStateReducer: AgentStateReducing {
    private let staleThreshold: TimeInterval
    private let purgeThreshold: TimeInterval

    public init(
        staleThreshold: TimeInterval = 20,
        purgeThreshold: TimeInterval = 600
    ) {
        self.staleThreshold = staleThreshold
        self.purgeThreshold = purgeThreshold
    }

    public func reduce(
        event: AgentObservationEvent,
        current: AgentRuntimeSnapshot?
    ) -> (snapshot: AgentRuntimeSnapshot?, permissionUpdate: PermissionRequestSnapshot?) {
        var snapshot = current ?? AgentRuntimeSnapshot(
            provider: event.provider,
            sessionID: event.sessionID,
            workspacePath: event.workspacePath,
            taskTitle: event.title ?? inferredTaskTitle(from: event)
        )

        snapshot.workspacePath = event.workspacePath ?? snapshot.workspacePath
        snapshot.taskTitle = preferredTitle(current: snapshot.taskTitle, event: event)
        snapshot.lastTraceID = event.traceID
        snapshot.lastUpdatedAt = event.timestamp

        if let message = event.message, !message.isEmpty {
            snapshot.latestProgressText = message
        }

        if event.kind == .sessionStarted {
            snapshot.startedAt = event.timestamp
        }

        if event.kind == .quotaUpdated {
            snapshot.quotaStatus = AgentQuotaStatus(
                availability: event.metadata["availability"].flatMap(QuotaAvailability.init(rawValue:)) ?? .unknown,
                remainingValue: event.metadata["remainingValue"].flatMap(Double.init),
                unit: event.metadata["unit"],
                sourceLabel: event.metadata["sourceLabel"],
                updatedAt: event.timestamp
            )
        }

        var permissionUpdate: PermissionRequestSnapshot?
        let previousPhase = snapshot.rawPhase

        switch event.kind {
        case .sessionStarted:
            snapshot.rawPhase = .booting
            snapshot.isWorking = false
            snapshot.isFinished = false
            snapshot.isFailed = false
        case .taskStarted, .toolStarted, .agentOutput, .heartbeat:
            snapshot.rawPhase = .running
            snapshot.isWorking = true
            snapshot.isFinished = false
            snapshot.isFailed = false
            snapshot.needsInput = false
            snapshot.needsPermission = false
        case .toolFinished:
            snapshot.rawPhase = .running
            snapshot.isWorking = true
            snapshot.needsInput = false
            snapshot.needsPermission = false
        case .waitingInput:
            snapshot.rawPhase = .waitingInput
            snapshot.isWorking = false
            snapshot.needsInput = true
            snapshot.needsPermission = false
        case .waitingApproval:
            snapshot.rawPhase = .waitingApproval
            snapshot.isWorking = false
            snapshot.needsInput = false
            snapshot.needsPermission = true
            permissionUpdate = PermissionRequestSnapshot(
                provider: event.provider,
                sessionID: event.sessionID,
                toolName: event.metadata["toolName"] ?? "Unknown",
                summary: event.message ?? event.title ?? "等待权限确认",
                createdAt: event.timestamp,
                source: event.rawSource ?? event.provider.displayName
            )
        case .taskFinished:
            snapshot.rawPhase = .finished
            snapshot.isWorking = false
            snapshot.isFinished = true
            snapshot.isFailed = false
            snapshot.needsInput = false
            snapshot.needsPermission = false
        case .taskFailed, .collectorError:
            snapshot.rawPhase = .failed
            snapshot.isWorking = false
            snapshot.isFinished = false
            snapshot.isFailed = true
            snapshot.needsInput = false
            snapshot.needsPermission = false
        case .quotaUpdated:
            break
        }

        if snapshot.rawPhase != previousPhase {
            snapshot.stateEnteredAt = event.timestamp
        }

        snapshot.providerMeta.merge(event.metadata) { _, newValue in newValue }
        return (snapshot, permissionUpdate)
    }

    public func inferBoardState(snapshot: AgentRuntimeSnapshot) -> BoardState {
        if snapshot.needsPermission || snapshot.rawPhase == .waitingApproval {
            return .approve
        }
        if snapshot.needsInput || snapshot.rawPhase == .waitingInput {
            return .input
        }
        if snapshot.isFailed || snapshot.rawPhase == .failed {
            return .error
        }
        if snapshot.isFinished || snapshot.rawPhase == .finished {
            return .check
        }
        return .run
    }

    public func refreshedSnapshots(
        from snapshots: [AgentRuntimeSnapshot],
        at now: Date
    ) -> [AgentRuntimeSnapshot] {
        snapshots.compactMap { snapshot in
            let age = now.timeIntervalSince(snapshot.lastUpdatedAt)
            guard age < purgeThreshold else { return nil }

            var mutable = snapshot
            if age >= staleThreshold,
               snapshot.isWorking,
               !snapshot.isFinished,
               !snapshot.isFailed,
               !snapshot.needsInput,
               !snapshot.needsPermission {
                if mutable.rawPhase != .stale {
                    mutable.rawPhase = .stale
                    mutable.stateEnteredAt = now
                }
            }
            return mutable
        }
    }

    private func inferredTaskTitle(from event: AgentObservationEvent) -> String {
        if let workspace = event.workspacePath?.split(separator: "/").last, !workspace.isEmpty {
            return String(workspace)
        }
        return event.provider.displayName
    }

    private func preferredTitle(current: String, event: AgentObservationEvent) -> String {
        if let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inferredTaskTitle(from: event)
        }
        return current
    }
}

public struct DefaultTaskBoardSnapshotBuilder: TaskBoardSnapshotBuilding {
    private let reducer: any AgentStateReducing

    public init(reducer: any AgentStateReducing) {
        self.reducer = reducer
    }

    public func makeSnapshot(
        from runtimeSnapshots: [AgentRuntimeSnapshot],
        selection: TaskBoardSelectionState,
        generatedAt: Date
    ) -> TaskBoardSnapshot {
        let sorted = runtimeSnapshots.sorted { lhs, rhs in
            let lhsState = reducer.inferBoardState(snapshot: lhs)
            let rhsState = reducer.inferBoardState(snapshot: rhs)

            if lhsState.priority != rhsState.priority {
                return lhsState.priority > rhsState.priority
            }
            if lhs.stateEnteredAt != rhs.stateEnteredAt {
                return lhs.stateEnteredAt > rhs.stateEnteredAt
            }
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }

        let visibleSnapshots = Array(sorted.prefix(5))
        let selectedCardID = selection.selectedCardID ?? visibleSnapshots.first?.id
        let cards = visibleSnapshots.map { snapshot in
            TaskCardSnapshot(
                id: snapshot.id,
                provider: snapshot.provider,
                title: snapshot.taskTitle,
                boardState: reducer.inferBoardState(snapshot: snapshot),
                progressText: snapshot.latestProgressText,
                elapsedSeconds: max(0, Int(generatedAt.timeIntervalSince(snapshot.startedAt))),
                isSelected: snapshot.id == selectedCardID
            )
        }
        let providerSummaries = AgentProvider.allCases.map { provider in
            let providerSnapshots = sorted.filter { $0.provider == provider }
            return ProviderSummarySnapshot(
                provider: provider,
                activeTaskCount: providerSnapshots.count,
                waitingInputCount: providerSnapshots.filter { reducer.inferBoardState(snapshot: $0) == .input }.count,
                waitingApprovalCount: providerSnapshots.filter { reducer.inferBoardState(snapshot: $0) == .approve }.count,
                errorCount: providerSnapshots.filter { reducer.inferBoardState(snapshot: $0) == .error }.count,
                quotaStatus: providerSnapshots.last?.quotaStatus ?? .unknown
            )
        }

        let layoutMode: TaskBoardLayoutMode = cards.count <= 2 ? .stretched : .fixed
        return TaskBoardSnapshot(
            cards: cards,
            hiddenCount: max(0, sorted.count - cards.count),
            selectedCardID: selectedCardID,
            isGlobalBrowseMode: selection.isGlobalBrowseMode,
            layoutMode: layoutMode,
            providerSummaries: providerSummaries,
            generatedAt: generatedAt
        )
    }
}

public struct DefaultEmbeddedDisplaySnapshotBuilder: EmbeddedDisplaySnapshotBuilding {
    public init() {}

    public func makeSnapshot(
        sequence: UInt64,
        mode: EmbeddedDisplayMode,
        taskBoard: TaskBoardSnapshot?,
        waveform: AudioWaveformSnapshot?,
        generatedAt: Date
    ) -> EmbeddedDisplaySnapshot {
        EmbeddedDisplaySnapshot(
            sequence: sequence,
            mode: mode,
            taskBoard: taskBoard,
            waveform: waveform,
            generatedAt: generatedAt
        )
    }
}
