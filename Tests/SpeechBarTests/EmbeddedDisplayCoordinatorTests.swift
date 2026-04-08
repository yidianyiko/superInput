import Foundation
import Testing
@testable import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("EmbeddedDisplayCoordinator", .serialized)
struct EmbeddedDisplayCoordinatorTests {
    @Test
    @MainActor
    func coalescesRapidAudioLevelUpdatesIntoSingleSnapshotRebuild() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let voiceCoordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            sleepClock: ImmediateSleepClock()
        )
        let diagnostics = DiagnosticsCoordinator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("EmbeddedDisplayCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        )
        let reducer = DefaultAgentStateReducer(staleThreshold: 30, purgeThreshold: 3_600)
        let agentMonitorCoordinator = AgentMonitorCoordinator(
            collectors: [],
            reducer: reducer,
            snapshotBuilder: DefaultTaskBoardSnapshotBuilder(reducer: reducer),
            diagnostics: diagnostics
        )
        let builder = CountingEmbeddedDisplaySnapshotBuilder()
        let coordinator = EmbeddedDisplayCoordinator(
            voiceCoordinator: voiceCoordinator,
            monitorCoordinator: agentMonitorCoordinator,
            diagnostics: diagnostics,
            displayBuilder: builder,
            encoder: EmbeddedDisplayEncoder(),
            transport: LoopbackBoardTransport(),
            snapshotRebuildDebounceDuration: .milliseconds(120)
        )

        voiceCoordinator.start()
        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            voiceCoordinator.sessionState == .recording
        }

        try await Task.sleep(for: .milliseconds(180))
        let baselineCallCount = builder.callCount

        let startedAt = Date()
        for index in 0..<12 {
            audio.emit(
                level: AudioLevelSample(
                    level: Double(index + 1) / 12.0,
                    peak: Double(index + 1) / 12.0,
                    capturedAt: startedAt.addingTimeInterval(Double(index) * 0.01)
                )
            )
        }

        try await Task.sleep(for: .milliseconds(60))
        #expect(builder.callCount == baselineCallCount)

        try await eventually {
            builder.callCount == baselineCallCount + 1
        }
    }
}

private final class CountingEmbeddedDisplaySnapshotBuilder: EmbeddedDisplaySnapshotBuilding, @unchecked Sendable {
    private(set) var callCount = 0

    func makeSnapshot(
        sequence: UInt64,
        mode: EmbeddedDisplayMode,
        taskBoard: TaskBoardSnapshot?,
        waveform: AudioWaveformSnapshot?,
        generatedAt: Date
    ) -> EmbeddedDisplaySnapshot {
        callCount += 1
        return EmbeddedDisplaySnapshot(
            sequence: sequence,
            mode: mode,
            taskBoard: taskBoard,
            waveform: waveform,
            generatedAt: generatedAt
        )
    }
}

private enum EmbeddedDisplayCoordinatorTestFailure: Error {
    case timeout
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(20),
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if predicate() {
            return
        }
        try await clock.sleep(for: pollInterval)
    }

    throw EmbeddedDisplayCoordinatorTestFailure.timeout
}
