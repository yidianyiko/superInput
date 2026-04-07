import Combine
import Foundation
import SpeechBarDomain

@MainActor
public final class AgentMonitorCoordinator: ObservableObject {
    @Published public private(set) var runtimeSnapshots: [AgentRuntimeSnapshot] = []
    @Published public private(set) var taskBoardSnapshot: TaskBoardSnapshot = TaskBoardSnapshot(
        cards: [],
        hiddenCount: 0,
        selectedCardID: nil,
        isGlobalBrowseMode: false,
        layoutMode: .stretched,
        providerSummaries: [],
        generatedAt: Date()
    )
    @Published public private(set) var collectorHealth: [AgentProvider: CollectorHealthSnapshot] = [:]
    @Published public private(set) var permissionRequests: [PermissionRequestSnapshot] = []
    @Published public private(set) var stateTransitions: [StateTransitionNotification] = []
    @Published public private(set) var lastObservationAt: Date?

    public let transitionNotifier: StateTransitionNotifier

    private let collectors: [any AgentCollector]
    private let reducer: any AgentStateReducing
    private let snapshotBuilder: any TaskBoardSnapshotBuilding
    private let diagnostics: DiagnosticsCoordinator

    private var selectionState = TaskBoardSelectionState()
    private var collectorTasks: [Task<Void, Never>] = []
    private var maintenanceTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var acknowledgeTask: Task<Void, Never>?
    private var hasStarted = false

    public init(
        collectors: [any AgentCollector],
        reducer: any AgentStateReducing,
        snapshotBuilder: any TaskBoardSnapshotBuilding,
        diagnostics: DiagnosticsCoordinator,
        transitionNotifier: StateTransitionNotifier = StateTransitionNotifier()
    ) {
        self.collectors = collectors
        self.reducer = reducer
        self.snapshotBuilder = snapshotBuilder
        self.diagnostics = diagnostics
        self.transitionNotifier = transitionNotifier
    }

    deinit {
        collectorTasks.forEach { $0.cancel() }
        maintenanceTask?.cancel()
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        diagnostics.recordContext([
            "collectorCount": String(collectors.count),
            "providers": collectors.map(\.provider.rawValue).joined(separator: ",")
        ])

        for collector in collectors {
            let task = Task { [weak self] in
                await collector.start()
                await self?.refreshHealth()
                for await event in collector.events {
                    self?.handle(event: event)
                }
            }
            collectorTasks.append(task)
        }

        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self.refreshHealth()
                self.runMaintenance()
            }
        }
    }

    public func moveToNextCard() {
        guard !taskBoardSnapshot.cards.isEmpty else { return }
        let cards = taskBoardSnapshot.cards
        let currentIndex = cards.firstIndex(where: { $0.id == selectionState.selectedCardID }) ?? 0
        let nextIndex = (currentIndex + 1) % cards.count
        selectCard(id: cards[nextIndex].id, userInitiated: true)
    }

    public func moveToPreviousCard() {
        guard !taskBoardSnapshot.cards.isEmpty else { return }
        let cards = taskBoardSnapshot.cards
        let currentIndex = cards.firstIndex(where: { $0.id == selectionState.selectedCardID }) ?? 0
        let previousIndex = (currentIndex - 1 + cards.count) % cards.count
        selectCard(id: cards[previousIndex].id, userInitiated: true)
    }

    public func dismissSelectedCard() {
        guard let selectedCardID = selectionState.selectedCardID else { return }
        runtimeSnapshots.removeAll { $0.id == selectedCardID }
        permissionRequests.removeAll { "\($0.provider.rawValue):\($0.sessionID)" == selectedCardID }
        selectionState.selectedCardID = runtimeSnapshots.first?.id
        rebuildBoardSnapshot(reason: "selection-dismiss")
    }

    public func setGlobalBrowseMode(_ enabled: Bool) {
        selectionState.isGlobalBrowseMode = enabled
        rebuildBoardSnapshot(reason: "browse-mode")
    }

    public func selectCard(id: String, userInitiated: Bool) {
        selectionState.selectedCardID = id
        rebuildBoardSnapshot(reason: "selection-update")
        guard userInitiated else { return }
        acknowledgeCompletedCardIfNeeded(id: id)
    }

    public func runDemoSequence() {
        startDemoSequence(kind: .standard)
    }

    public func runErrorDemoSequence() {
        startDemoSequence(kind: .error)
    }

    public func stopDemoSequence() {
        demoTask?.cancel()
        demoTask = nil
    }

    private func handle(event: AgentObservationEvent) {
        lastObservationAt = event.timestamp
        diagnostics.recordObservation(event)

        let startedAt = Date()
        let currentSnapshot = runtimeSnapshots.first { $0.id == "\(event.provider.rawValue):\(event.sessionID)" }
        let reduction = reducer.reduce(event: event, current: currentSnapshot)
        let previousBoardState = currentSnapshot.map { reducer.inferBoardState(snapshot: $0) }

        let snapshotID = "\(event.provider.rawValue):\(event.sessionID)"
        runtimeSnapshots.removeAll { $0.id == snapshotID }
        if let snapshot = reduction.snapshot {
            runtimeSnapshots.append(snapshot)
            let newBoardState = reducer.inferBoardState(snapshot: snapshot)
            if previousBoardState != newBoardState {
                let transition = StateTransitionNotification(
                    sessionID: event.sessionID,
                    provider: event.provider,
                    from: previousBoardState,
                    to: newBoardState
                )
                stateTransitions.insert(transition, at: 0)
                if stateTransitions.count > 40 {
                    stateTransitions = Array(stateTransitions.prefix(40))
                }
                transitionNotifier.notify(transition)
            }
        }

        if let permissionUpdate = reduction.permissionUpdate {
            appendPermissionRequest(permissionUpdate)
        } else {
            resolvePermissionRequestsIfNeeded(for: event.provider, sessionID: event.sessionID)
        }

        let reduceDuration = Date().timeIntervalSince(startedAt)
        diagnostics.recordDiagnostic(
            subsystem: "agent-monitor.reduce",
            severity: .info,
            message: "Reduced observation event",
            metadata: [
                "provider": event.provider.rawValue,
                "kind": event.kind.rawValue,
                "durationMs": String(Int(reduceDuration * 1_000))
            ],
            traceID: event.traceID
        )

        rebuildBoardSnapshot(reason: "event-\(event.kind.rawValue)")
    }

    private func appendPermissionRequest(_ request: PermissionRequestSnapshot) {
        if let index = permissionRequests.firstIndex(where: { $0.provider == request.provider && $0.sessionID == request.sessionID && !$0.isResolved }) {
            permissionRequests[index] = request
        } else {
            permissionRequests.insert(request, at: 0)
        }
        if permissionRequests.count > 80 {
            permissionRequests = Array(permissionRequests.prefix(80))
        }
    }

    private func resolvePermissionRequestsIfNeeded(for provider: AgentProvider, sessionID: String) {
        guard let snapshot = runtimeSnapshots.first(where: { $0.provider == provider && $0.sessionID == sessionID }) else {
            return
        }
        guard !snapshot.needsPermission else { return }
        permissionRequests = permissionRequests.map { request in
            guard request.provider == provider, request.sessionID == sessionID else { return request }
            var updated = request
            updated.isResolved = true
            return updated
        }
    }

    private func rebuildBoardSnapshot(reason: String) {
        let buildStartedAt = Date()
        let snapshot = snapshotBuilder.makeSnapshot(
            from: runtimeSnapshots,
            selection: selectionState,
            generatedAt: Date()
        )
        taskBoardSnapshot = snapshot
        selectionState.selectedCardID = snapshot.selectedCardID
        diagnostics.recordSnapshots(
            runtimeSnapshots: runtimeSnapshots,
            taskBoardSnapshot: snapshot,
            embeddedDisplaySnapshot: nil
        )

        let buildDuration = Date().timeIntervalSince(buildStartedAt)
        diagnostics.recordDiagnostic(
            subsystem: "agent-monitor.board",
            severity: .info,
            message: "Rebuilt task board snapshot",
            metadata: [
                "reason": reason,
                "cardCount": String(snapshot.cards.count),
                "hiddenCount": String(snapshot.hiddenCount),
                "durationMs": String(Int(buildDuration * 1_000))
            ]
        )
    }

    private func refreshHealth() async {
        for collector in collectors {
            let health = await collector.healthSnapshot()
            collectorHealth[collector.provider] = health
        }
    }

    private func runMaintenance() {
        let refreshed = reducer.refreshedSnapshots(from: runtimeSnapshots, at: Date())
        if refreshed != runtimeSnapshots {
            runtimeSnapshots = refreshed
            rebuildBoardSnapshot(reason: "maintenance")
        }
    }

    private func acknowledgeCompletedCardIfNeeded(id: String) {
        guard let snapshot = runtimeSnapshots.first(where: { $0.id == id }) else { return }
        let boardState = reducer.inferBoardState(snapshot: snapshot)
        guard boardState == .check else { return }

        acknowledgeTask?.cancel()
        acknowledgeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            self.runtimeSnapshots.removeAll { $0.id == id }
            self.permissionRequests.removeAll { "\($0.provider.rawValue):\($0.sessionID)" == id }
            self.selectionState.selectedCardID = self.runtimeSnapshots.first?.id
            self.rebuildBoardSnapshot(reason: "acknowledged-complete")
            self.diagnostics.recordDiagnostic(
                subsystem: "agent-monitor.ack",
                severity: .info,
                message: "Acknowledged completed task",
                metadata: ["id": id]
            )
        }
    }

    private func startDemoSequence(kind: DemoSequenceKind) {
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            guard let self else { return }
            let sessionSuffix = String(UUID().uuidString.prefix(6))
            switch kind {
            case .standard:
                let sessionID = "demo-codex-\(sessionSuffix)"
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .sessionStarted,
                    title: "Demo Task",
                    message: "session started"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .taskStarted,
                    title: "Demo Task",
                    message: "开始执行"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .agentOutput,
                    message: "处理中..."
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .waitingInput,
                    message: "等待输入"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .agentOutput,
                    message: "继续执行"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .waitingApproval,
                    message: "需要授权",
                    metadata: ["toolName": "shell_command"]
                )
                try? await Task.sleep(for: .seconds(2))
                await emitDemoEvent(
                    provider: .codexCLI,
                    sessionID: sessionID,
                    kind: .taskFinished,
                    message: "任务完成"
                )
            case .error:
                let sessionID = "demo-cursor-\(sessionSuffix)"
                await emitDemoEvent(
                    provider: .cursorAgent,
                    sessionID: sessionID,
                    kind: .sessionStarted,
                    title: "Demo Error Task",
                    message: "session started"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .cursorAgent,
                    sessionID: sessionID,
                    kind: .taskStarted,
                    title: "Demo Error Task",
                    message: "开始执行"
                )
                try? await Task.sleep(for: .seconds(1))
                await emitDemoEvent(
                    provider: .cursorAgent,
                    sessionID: sessionID,
                    kind: .taskFailed,
                    message: "执行失败"
                )
            }
        }
    }

    private func emitDemoEvent(
        provider: AgentProvider,
        sessionID: String,
        kind: AgentObservationKind,
        title: String? = nil,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        let event = AgentObservationEvent(
            provider: provider,
            sessionID: sessionID,
            kind: kind,
            title: title,
            message: message,
            workspacePath: "/Users/lixingting/Desktop/StartUp/Code",
            rawSource: "demo-sequence",
            metadata: metadata
        )
        handle(event: event)
    }
}

private enum DemoSequenceKind {
    case standard
    case error
}
