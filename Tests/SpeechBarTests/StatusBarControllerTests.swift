import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("StatusBarController")
struct StatusBarControllerTests {
    @Test
    @MainActor
    func defersHomeWindowCreationUntilExplicitOpen() {
        let dependencies = makeStatusBarDependencies()
        var factoryCallCount = 0
        let homeWindow = MockHomeWindowController()

        let controller = StatusBarController(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            pushToTalkSource: dependencies.pushToTalkSource,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            homeWindowControllerFactory: {
                factoryCallCount += 1
                return homeWindow
            }
        )

        #expect(factoryCallCount == 0)

        controller.showHomeWindowForLocalModelSetupIfNeeded()

        #expect(factoryCallCount == 1)
        #expect(homeWindow.showCallCount == 1)
    }

    @Test
    @MainActor
    func reusesHomeWindowControllerAcrossMultipleOpenRequests() {
        let dependencies = makeStatusBarDependencies()
        var factoryCallCount = 0
        let homeWindow = MockHomeWindowController()

        let controller = StatusBarController(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            pushToTalkSource: dependencies.pushToTalkSource,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            homeWindowControllerFactory: {
                factoryCallCount += 1
                return homeWindow
            }
        )

        controller.showHomeWindowForLocalModelSetupIfNeeded()
        controller.showHomeWindowForLocalModelSetupIfNeeded()

        #expect(factoryCallCount == 1)
        #expect(homeWindow.showCallCount == 2)
    }
}

@MainActor
private func makeStatusBarDependencies() -> StatusBarTestDependencies {
    let defaults = UserDefaults(suiteName: "StatusBarControllerTests.\(UUID().uuidString)")!
    let diagnosticsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StatusBarControllerTests-\(UUID().uuidString)", isDirectory: true)
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
    return StatusBarTestDependencies(
        coordinator: coordinator,
        agentMonitorCoordinator: agentMonitorCoordinator,
        embeddedDisplayCoordinator: embeddedDisplayCoordinator,
        diagnosticsCoordinator: diagnosticsCoordinator,
        pushToTalkSource: pushToTalkSource,
        userProfileStore: userProfileStore,
        audioInputSettingsStore: audioInputSettingsStore,
        modelSettingsStore: modelSettingsStore,
        polishPlaygroundStore: polishPlaygroundStore,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore,
        memoryConstellationStore: memoryConstellationStore,
        memoryFeatureFlagStore: memoryFeatureFlagStore
    )
}

@MainActor
private struct StatusBarTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let pushToTalkSource: OnScreenPushToTalkSource
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let polishPlaygroundStore: PolishPlaygroundStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let memoryConstellationStore: MemoryConstellationStore
    let memoryFeatureFlagStore: MemoryFeatureFlagStore
}

@MainActor
private final class MockHomeWindowController: HomeWindowControlling {
    private(set) var showCallCount = 0

    func showWindowAndActivate() {
        showCallCount += 1
    }
}
