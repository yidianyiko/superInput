import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarInfrastructure

@Suite("AgentMonitorBuilders")
struct AgentMonitorBuildersTests {
    @Test
    func boardStatesAreOrderedByPriority() {
        let now = Date()
        let reducer = DefaultAgentStateReducer()
        let builder = DefaultTaskBoardSnapshotBuilder(reducer: reducer)

        let snapshots = [
            makeSnapshot(provider: .codexCLI, sessionID: "run", phase: .running, startedAt: now.addingTimeInterval(-20), stateEnteredAt: now.addingTimeInterval(-5)),
            makeSnapshot(provider: .claudeCode, sessionID: "check", phase: .finished, finished: true, startedAt: now.addingTimeInterval(-40), stateEnteredAt: now.addingTimeInterval(-4)),
            makeSnapshot(provider: .geminiCLI, sessionID: "input", phase: .waitingInput, needsInput: true, startedAt: now.addingTimeInterval(-60), stateEnteredAt: now.addingTimeInterval(-3)),
            makeSnapshot(provider: .cursorAgent, sessionID: "approve", phase: .waitingApproval, needsPermission: true, startedAt: now.addingTimeInterval(-80), stateEnteredAt: now.addingTimeInterval(-2)),
            makeSnapshot(provider: .claudeCode, sessionID: "error", phase: .failed, failed: true, startedAt: now.addingTimeInterval(-100), stateEnteredAt: now.addingTimeInterval(-1))
        ]

        let board = builder.makeSnapshot(
            from: snapshots,
            selection: TaskBoardSelectionState(),
            generatedAt: now
        )

        #expect(board.cards.map(\.boardState) == [.error, .input, .approve, .check, .run])
    }

    @Test
    func layoutAndHiddenCountFollowVisibleCardRules() {
        let now = Date()
        let reducer = DefaultAgentStateReducer()
        let builder = DefaultTaskBoardSnapshotBuilder(reducer: reducer)

        let shortBoard = builder.makeSnapshot(
            from: [
                makeSnapshot(provider: .codexCLI, sessionID: "1", phase: .running),
                makeSnapshot(provider: .claudeCode, sessionID: "2", phase: .running)
            ],
            selection: TaskBoardSelectionState(),
            generatedAt: now
        )
        #expect(shortBoard.layoutMode == .stretched)

        let longBoard = builder.makeSnapshot(
            from: (0..<6).map { index in
                makeSnapshot(
                    provider: AgentProvider.allCases[index % AgentProvider.allCases.count],
                    sessionID: "\(index)",
                    phase: .running,
                    stateEnteredAt: now.addingTimeInterval(Double(index))
                )
            },
            selection: TaskBoardSelectionState(),
            generatedAt: now
        )

        #expect(longBoard.layoutMode == .fixed)
        #expect(longBoard.cards.count == 5)
        #expect(longBoard.hiddenCount == 1)
    }

    @Test
    func staleAndExpiredSnapshotsAreMaintainedIncrementally() {
        let reducer = DefaultAgentStateReducer(staleThreshold: 20, purgeThreshold: 60)
        let base = Date(timeIntervalSince1970: 1_000)
        let staleCandidate = makeSnapshot(
            provider: .codexCLI,
            sessionID: "stale",
            phase: .running,
            startedAt: base,
            lastUpdatedAt: base,
            stateEnteredAt: base
        )
        let expired = makeSnapshot(
            provider: .claudeCode,
            sessionID: "expired",
            phase: .running,
            startedAt: base,
            lastUpdatedAt: base.addingTimeInterval(-100),
            stateEnteredAt: base
        )

        let refreshed = reducer.refreshedSnapshots(
            from: [staleCandidate, expired],
            at: base.addingTimeInterval(30)
        )

        #expect(refreshed.count == 1)
        #expect(refreshed.first?.rawPhase == .stale)
    }
}

private func makeSnapshot(
    provider: AgentProvider,
    sessionID: String,
    phase: AgentRawPhase,
    needsPermission: Bool = false,
    needsInput: Bool = false,
    finished: Bool = false,
    failed: Bool = false,
    startedAt: Date = Date(),
    lastUpdatedAt: Date = Date(),
    stateEnteredAt: Date = Date()
) -> AgentRuntimeSnapshot {
    AgentRuntimeSnapshot(
        provider: provider,
        sessionID: sessionID,
        taskTitle: provider.shortLabel + " " + sessionID,
        latestProgressText: "progress-\(sessionID)",
        rawPhase: phase,
        needsPermission: needsPermission,
        needsInput: needsInput,
        isWorking: phase == .running,
        isFinished: finished,
        isFailed: failed,
        startedAt: startedAt,
        lastUpdatedAt: lastUpdatedAt,
        stateEnteredAt: stateEnteredAt
    )
}
