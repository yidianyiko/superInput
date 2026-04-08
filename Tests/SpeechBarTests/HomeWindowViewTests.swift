import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("HomeWindowView")
struct HomeWindowViewTests {
    @Test
    @MainActor
    func agentMonitorUpdatesDoNotInvalidateRootViewOutsideMonitorSections() async throws {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.settings)
        var bodyEvaluationCount = 0

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            bodyEvaluationProbe: { bodyEvaluationCount += 1 }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

        hostingView.layoutSubtreeIfNeeded()
        let baselineCount = bodyEvaluationCount

        dependencies.agentMonitorCoordinator.setGlobalBrowseMode(true)
        try await Task.sleep(for: .milliseconds(80))
        hostingView.layoutSubtreeIfNeeded()

        #expect(bodyEvaluationCount == baselineCount)
    }

    @Test
    @MainActor
    func diagnosticsUpdatesDoNotInvalidateRootViewOutsideDebugSections() async throws {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.home)
        var bodyEvaluationCount = 0

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            bodyEvaluationProbe: { bodyEvaluationCount += 1 }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

        hostingView.layoutSubtreeIfNeeded()
        let baselineCount = bodyEvaluationCount

        dependencies.diagnosticsCoordinator.recordDiagnostic(
            subsystem: "test",
            severity: .info,
            message: "trigger update"
        )
        try await Task.sleep(for: .milliseconds(80))
        hostingView.layoutSubtreeIfNeeded()

        #expect(bodyEvaluationCount == baselineCount)
    }
}

@MainActor
private func makeHomeWindowDependencies() -> HomeWindowViewTestDependencies {
    let defaults = UserDefaults(suiteName: "HomeWindowViewTests.\(UUID().uuidString)")!
    let diagnosticsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HomeWindowViewTests-\(UUID().uuidString)", isDirectory: true)
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        sleepClock: ImmediateSleepClock()
    )
    let diagnosticsCoordinator = DiagnosticsCoordinator(baseDirectory: diagnosticsDirectory)
    let reducer = DefaultAgentStateReducer(staleThreshold: 30, purgeThreshold: 3_600)
    let agentMonitorCoordinator = AgentMonitorCoordinator(
        collectors: [],
        reducer: reducer,
        snapshotBuilder: DefaultTaskBoardSnapshotBuilder(reducer: reducer),
        diagnostics: diagnosticsCoordinator
    )
    let embeddedDisplayCoordinator = EmbeddedDisplayCoordinator(
        voiceCoordinator: coordinator,
        monitorCoordinator: agentMonitorCoordinator,
        diagnostics: diagnosticsCoordinator,
        displayBuilder: DefaultEmbeddedDisplaySnapshotBuilder(),
        encoder: EmbeddedDisplayEncoder(),
        transport: LoopbackBoardTransport()
    )
    let pushToTalkSource = OnScreenPushToTalkSource()
    let userProfileStore = UserProfileStore(defaults: defaults)
    let audioInputSettingsStore = AudioInputSettingsStore(defaults: defaults)
    let localWhisperModelStore = LocalWhisperModelStore(defaults: defaults)
    let senseVoiceModelStore = SenseVoiceModelStore(defaults: defaults)
    let modelSettingsStore = OpenAIModelSettingsStore(
        defaults: defaults,
        deepgramCredentialProvider: credentials,
        openAICredentialProvider: credentials,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore
    )
    let polishPlaygroundStore = PolishPlaygroundStore { _ in "" }
    let memoryFeatureFlagStore = MemoryFeatureFlagStore(defaults: defaults)
    let memoryConstellationStore = MemoryConstellationStore(
        catalog: nil,
        featureFlags: memoryFeatureFlagStore
    )
    let store = HomeWindowStore(coordinator: coordinator, defaults: defaults)
    return HomeWindowViewTestDependencies(
        coordinator: coordinator,
        agentMonitorCoordinator: agentMonitorCoordinator,
        embeddedDisplayCoordinator: embeddedDisplayCoordinator,
        diagnosticsCoordinator: diagnosticsCoordinator,
        store: store,
        userProfileStore: userProfileStore,
        audioInputSettingsStore: audioInputSettingsStore,
        modelSettingsStore: modelSettingsStore,
        polishPlaygroundStore: polishPlaygroundStore,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore,
        memoryConstellationStore: memoryConstellationStore,
        memoryFeatureFlagStore: memoryFeatureFlagStore,
        pushToTalkSource: pushToTalkSource
    )
}

@MainActor
private struct HomeWindowViewTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let store: HomeWindowStore
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let polishPlaygroundStore: PolishPlaygroundStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let memoryConstellationStore: MemoryConstellationStore
    let memoryFeatureFlagStore: MemoryFeatureFlagStore
    let pushToTalkSource: OnScreenPushToTalkSource
}
