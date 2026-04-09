import AppKit
import Combine
import MemoryCore
import MemoryExtraction
import MemoryStorageSQLite
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

        AppSingletonCoordinator().terminateOtherInstances(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
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
            let exitCode = await OffscreenHomeSnapshotRenderer.run(command)
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
    let boardEventSource: BoardEventFileHardwareEventSource
    let boardInputBridgeController: BoardInputBridgeController
    let hardwareSource: MergedHardwareEventSource
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let polishPlaygroundStore: PolishPlaygroundStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let windowSwitchOverlayStore: WindowSwitchOverlayStore
    let memoryFeatureFlagStore: MemoryFeatureFlagStore
    let memoryConstellationStore: MemoryConstellationStore
    let coordinator: VoiceSessionCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let statusBarController: StatusBarController
    let recordingOverlayController: RecordingOverlayController
    let transcriptInjectionOverlayController: TranscriptInjectionOverlayController
    let windowSwitchOverlayController: WindowSwitchOverlayController
    let speechProviderObservation: AnyCancellable

    init() {
        let pushToTalkSource = OnScreenPushToTalkSource()
        let globalShortcutSource = GlobalRightCommandPushToTalkSource()
        let rotaryTestSource = GlobalRotaryKeyTestSource()
        let boardEventSource = BoardEventFileHardwareEventSource()
        let boardInputBridgeController = BoardInputBridgeController()
        let hardwareSource = MergedHardwareEventSource(sources: [
            pushToTalkSource,
            globalShortcutSource,
            rotaryTestSource,
            boardEventSource
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
        HomeWindowStore.migrateThemeStorageIfNeeded(defaults: .standard)
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
        let polishPlaygroundStore = PolishPlaygroundStore { [userProfileStore] transcript in
            let context = await userProfileStore.currentContext()
            guard context.polishMode != .off else {
                throw PolishPlaygroundError.polishDisabled
            }
            return try await transcriptPostProcessor.polish(
                transcript: transcript,
                context: context
            )
        }
        let focusedTextTranscriptPublisher = FocusedTextTranscriptPublisher(
            applicationTracker: applicationTracker,
            promptForAccessibilityAtLaunch: true
        )
        let transcriptPublisher = CompositeTranscriptPublisher(publishers: [
            focusedTextTranscriptPublisher
        ])
        let diagnosticsCoordinator = DiagnosticsCoordinator()
        let memoryFeatureFlagStore = MemoryFeatureFlagStore()
        let memoryCoordinator: MemoryCoordinator?
        let memoryDemoSeeder: MemoryDemoSeeder?
        do {
            let memoryDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".slashvibe-memory.sqlite")
            let memoryKeyProvider = KeychainMemoryKeyProvider(service: "com.startup.speechbar.memory")
            let memoryStore = try MemoryStorageSQLiteStore(
                databaseURL: memoryDatabaseURL,
                keyProvider: memoryKeyProvider
            )
            memoryDemoSeeder = MemoryDemoSeeder(store: memoryStore)
            memoryCoordinator = MemoryCoordinator(
                store: memoryStore,
                extractor: DefaultMemoryExtractor()
            )
        } catch {
            diagnosticsCoordinator.recordMemoryEvent(
                "Failed to initialize memory storage",
                severity: .warning,
                metadata: ["error": error.localizedDescription]
            )
            memoryDemoSeeder = nil
            memoryCoordinator = nil
        }
        let memoryConstellationStore = MemoryConstellationStore(
            catalog: memoryCoordinator,
            featureFlags: memoryFeatureFlagStore
        )
        if let memoryDemoSeeder {
            Task {
                do {
                    let inserted = try await memoryDemoSeeder.seedMissingDemoMemories()
                    if inserted > 0 {
                        await memoryConstellationStore.reload()
                    }
                } catch {
                    diagnosticsCoordinator.recordMemoryEvent(
                        "Failed to seed memory demo data",
                        severity: .warning,
                        metadata: ["error": error.localizedDescription]
                    )
                }
            }
        }
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
        self.boardEventSource = boardEventSource
        self.boardInputBridgeController = boardInputBridgeController
        self.hardwareSource = hardwareSource
        self.userProfileStore = userProfileStore
        self.audioInputSettingsStore = audioInputSettingsStore
        self.modelSettingsStore = modelSettingsStore
        self.polishPlaygroundStore = polishPlaygroundStore
        self.localWhisperModelStore = localWhisperModelStore
        self.senseVoiceModelStore = senseVoiceModelStore
        self.windowSwitchOverlayStore = windowSwitchOverlayStore
        self.memoryFeatureFlagStore = memoryFeatureFlagStore
        self.memoryConstellationStore = memoryConstellationStore
        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardwareSource,
            audioInputSource: audioInputSource,
            transcriptionClient: transcriptionClient,
            credentialProvider: speechCredentialProvider,
            transcriptPublisher: transcriptPublisher,
            windowSwitcher: windowSwitcher,
            transcriptTargetCapturer: focusedTextTranscriptPublisher,
            focusedSnapshotProvider: focusedTextTranscriptPublisher,
            userProfileProvider: userProfileStore,
            transcriptPostProcessor: transcriptPostProcessor,
            memoryRecorder: memoryCoordinator,
            memoryRetriever: memoryCoordinator,
            diagnostics: diagnosticsCoordinator,
            memoryCaptureEnabled: { [memoryFeatureFlagStore] in
                await MainActor.run { memoryFeatureFlagStore.captureEnabled }
            },
            memoryRecallEnabled: { [memoryFeatureFlagStore] in
                await MainActor.run { memoryFeatureFlagStore.recallEnabled }
            },
            memoryOptedOutApps: {
                Set(UserDefaults.standard.stringArray(forKey: "memory.optedOutApps") ?? [])
            },
            memoryOptedOutFieldLabels: {
                Set(UserDefaults.standard.stringArray(forKey: "memory.optedOutFieldLabels") ?? [])
            }
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
            polishPlaygroundStore: polishPlaygroundStore,
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore,
            memoryConstellationStore: memoryConstellationStore,
            memoryFeatureFlagStore: memoryFeatureFlagStore
        )
        self.recordingOverlayController = RecordingOverlayController(coordinator: coordinator)
        self.transcriptInjectionOverlayController = TranscriptInjectionOverlayController(
            coordinator: coordinator,
            targetProvider: focusedTextTranscriptPublisher
        )
        self.windowSwitchOverlayController = WindowSwitchOverlayController(store: windowSwitchOverlayStore)

        if modelSettingsStore.isFreshInstall && localWhisperModelStore.shouldShowInstallPrompt {
            statusBarController.showHomeWindowForLocalModelSetupIfNeeded()
        }
    }
}
