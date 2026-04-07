import AppKit
import Combine
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import SwiftUI

@main
struct SlashVibeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let dependencies: AppDependencies?

    init() {
        if OffscreenHomeSnapshotRuntime.command != nil {
            self.dependencies = nil
            return
        }

        SlashVibeMigration.runIfNeeded()
        self.dependencies = AppDependencies()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .defaultSize(width: 1, height: 1)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let command = OffscreenHomeSnapshotRuntime.command else {
            return
        }

        Task { @MainActor in
            let exitCode = OffscreenHomeSnapshotRenderer.run(command)
            fflush(stdout)
            fflush(stderr)
            exit(exitCode)
        }
    }
}

@MainActor
private struct AppDependencies {
    let pushToTalkSource: OnScreenPushToTalkSource
    let globalShortcutSource: GlobalRightCommandPushToTalkSource
    let rotaryTestSource: GlobalRotaryKeyTestSource
    let hardwareSource: MergedHardwareEventSource
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let windowSwitchOverlayStore: WindowSwitchOverlayStore
    let coordinator: VoiceSessionCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let statusBarController: StatusBarController
    let recordingOverlayController: RecordingOverlayController
    let windowSwitchOverlayController: WindowSwitchOverlayController
    let speechProviderObservation: AnyCancellable

    init() {
        let pushToTalkSource = OnScreenPushToTalkSource()
        let globalShortcutSource = GlobalRightCommandPushToTalkSource()
        let rotaryTestSource = GlobalRotaryKeyTestSource()
        let hardwareSource = MergedHardwareEventSource(sources: [
            pushToTalkSource,
            globalShortcutSource,
            rotaryTestSource
        ])
        let applicationTracker = FrontmostApplicationTracker()
        let windowSwitchOverlayStore = WindowSwitchOverlayStore()
        let windowSwitcher = SystemWindowSwitcher(
            applicationTracker: applicationTracker,
            previewPublisher: windowSwitchOverlayStore
        )
        let audioInputSettingsStore = AudioInputSettingsStore()
        let audioInputSource = MacBuiltInMicSource(
            preferredDeviceUIDProvider: {
                AudioInputSettingsStore.preferredDeviceUID()
            }
        )
        let localWhisperModelStore = LocalWhisperModelStore()
        let senseVoiceModelStore = SenseVoiceModelStore()
        let deepgramTranscriptionClient = DeepgramPrerecordedClient()
        let whisperTranscriptionClient = OpenAIWhisperTranscriptionClient()
        let localWhisperTranscriptionClient = LocalWhisperTranscriptionClient()
        let senseVoiceTranscriptionClient = SenseVoiceTranscriptionClient(modelStore: senseVoiceModelStore)
        let deepgramCredentialProvider = LocalCredentialProvider()
        let openAICredentialProvider = LocalCredentialProvider(account: "openai-api-key")
        let modelSettingsStore = OpenAIModelSettingsStore(
            deepgramCredentialProvider: deepgramCredentialProvider,
            openAICredentialProvider: openAICredentialProvider,
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore
        )
        localWhisperModelStore.prepareForLaunch(showFirstInstallPrompt: modelSettingsStore.isFreshInstall)
        senseVoiceModelStore.prepareForLaunch(showFirstInstallPrompt: false)
        let localWhisperCredentialProvider = LocalWhisperModelCredentialProvider(
            localWhisperModelsDirectory: localWhisperModelStore.modelsDirectory,
            defaultLocalWhisperModelName: localWhisperModelStore.defaultModel.name
        )
        let localSenseVoiceCredentialProvider = LocalSenseVoiceModelCredentialProvider(
            localSenseVoiceModelsDirectory: senseVoiceModelStore.modelsDirectory,
            defaultLocalSenseVoiceModelName: senseVoiceModelStore.defaultModel.name,
            senseVoiceRuntimeDirectory: senseVoiceModelStore.runtimeDirectory
        )
        let transcriptionClient = SwitchableSpeechTranscriptionClient(
            deepgramClient: deepgramTranscriptionClient,
            whisperClient: whisperTranscriptionClient,
            localWhisperClient: localWhisperTranscriptionClient,
            localSenseVoiceClient: senseVoiceTranscriptionClient,
            localWhisperModelsDirectory: localWhisperModelStore.modelsDirectory,
            defaultLocalWhisperModelName: localWhisperModelStore.defaultModel.name,
            localSenseVoiceModelsDirectory: senseVoiceModelStore.modelsDirectory,
            defaultLocalSenseVoiceModelName: senseVoiceModelStore.defaultModel.name
        )
        let speechCredentialProvider = SwitchingSpeechCredentialProvider(
            deepgramCredentialProvider: deepgramCredentialProvider,
            openAICredentialProvider: openAICredentialProvider,
            localWhisperCredentialProvider: localWhisperCredentialProvider,
            localSenseVoiceCredentialProvider: localSenseVoiceCredentialProvider
        )
        let researchClient = OpenAIResponsesResearchClient(
            credentialProvider: openAICredentialProvider,
            configurationProvider: modelSettingsStore
        )
        let userProfileStore = UserProfileStore(
            researchClient: researchClient
        )
        let transcriptPostProcessor = OpenAIResponsesTranscriptPostProcessor(
            credentialProvider: openAICredentialProvider,
            configurationProvider: modelSettingsStore
        )
        let focusedTextTranscriptPublisher = FocusedTextTranscriptPublisher(
            applicationTracker: applicationTracker,
            promptForAccessibilityAtLaunch: true
        )
        let transcriptPublisher = CompositeTranscriptPublisher(publishers: [
            focusedTextTranscriptPublisher
        ])
        let diagnosticsCoordinator = DiagnosticsCoordinator()
        let registry = DefaultAgentRegistry()
        let collectors = registry.makeEnabledCollectors()
        let reducer = DefaultAgentStateReducer(
            staleThreshold: 30,
            purgeThreshold: 3600
        )
        let taskBoardSnapshotBuilder = DefaultTaskBoardSnapshotBuilder(reducer: reducer)
        let embeddedSnapshotBuilder = DefaultEmbeddedDisplaySnapshotBuilder()
        let transport: any EmbeddedBoardTransport = LoopbackBoardTransport()

        self.pushToTalkSource = pushToTalkSource
        self.globalShortcutSource = globalShortcutSource
        self.rotaryTestSource = rotaryTestSource
        self.hardwareSource = hardwareSource
        self.userProfileStore = userProfileStore
        self.audioInputSettingsStore = audioInputSettingsStore
        self.modelSettingsStore = modelSettingsStore
        self.localWhisperModelStore = localWhisperModelStore
        self.senseVoiceModelStore = senseVoiceModelStore
        self.windowSwitchOverlayStore = windowSwitchOverlayStore
        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardwareSource,
            audioInputSource: audioInputSource,
            transcriptionClient: transcriptionClient,
            credentialProvider: speechCredentialProvider,
            transcriptPublisher: transcriptPublisher,
            windowSwitcher: windowSwitcher,
            transcriptTargetCapturer: focusedTextTranscriptPublisher,
            userProfileProvider: userProfileStore,
            transcriptPostProcessor: transcriptPostProcessor
        )
        self.coordinator = coordinator
        self.diagnosticsCoordinator = diagnosticsCoordinator
        let agentMonitorCoordinator = AgentMonitorCoordinator(
            collectors: collectors,
            reducer: reducer,
            snapshotBuilder: taskBoardSnapshotBuilder,
            diagnostics: diagnosticsCoordinator
        )
        self.agentMonitorCoordinator = agentMonitorCoordinator
        let embeddedDisplayCoordinator = EmbeddedDisplayCoordinator(
            voiceCoordinator: coordinator,
            monitorCoordinator: agentMonitorCoordinator,
            diagnostics: diagnosticsCoordinator,
            displayBuilder: embeddedSnapshotBuilder,
            encoder: EmbeddedDisplayEncoder(),
            transport: transport
        )
        self.embeddedDisplayCoordinator = embeddedDisplayCoordinator
        self.speechProviderObservation = modelSettingsStore.$configuration
            .map(\.speechProvider)
            .removeDuplicates()
            .sink { _ in
                coordinator.refreshCredentialStatus()
            }
        coordinator.start()
        agentMonitorCoordinator.start()
        embeddedDisplayCoordinator.start()
        self.statusBarController = StatusBarController(
            coordinator: coordinator,
            agentMonitorCoordinator: agentMonitorCoordinator,
            embeddedDisplayCoordinator: embeddedDisplayCoordinator,
            diagnosticsCoordinator: diagnosticsCoordinator,
            pushToTalkSource: pushToTalkSource,
            userProfileStore: userProfileStore,
            audioInputSettingsStore: audioInputSettingsStore,
            modelSettingsStore: modelSettingsStore,
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore
        )
        self.recordingOverlayController = RecordingOverlayController(coordinator: coordinator)
        self.windowSwitchOverlayController = WindowSwitchOverlayController(store: windowSwitchOverlayStore)

        if modelSettingsStore.isFreshInstall && localWhisperModelStore.shouldShowInstallPrompt {
            statusBarController.showHomeWindowForLocalModelSetupIfNeeded()
        }
    }
}
