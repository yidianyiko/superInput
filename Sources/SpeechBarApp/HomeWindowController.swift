import AppKit
import SpeechBarApplication
import SpeechBarInfrastructure
import SwiftUI

@MainActor
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let store: HomeWindowStore
    private let memoryConstellationStore: MemoryConstellationStore
    private let agentMonitorCoordinator: AgentMonitorCoordinator
    private let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    private let diagnosticsCoordinator: DiagnosticsCoordinator
    private let userProfileStore: UserProfileStore
    private let modelSettingsStore: OpenAIModelSettingsStore
    private let polishPlaygroundStore: PolishPlaygroundStore
    private let audioInputSettingsStore: AudioInputSettingsStore
    private let localWhisperModelStore: LocalWhisperModelStore
    private let senseVoiceModelStore: SenseVoiceModelStore
    private let memoryFeatureFlagStore: MemoryFeatureFlagStore

    init(
        coordinator: VoiceSessionCoordinator,
        agentMonitorCoordinator: AgentMonitorCoordinator,
        embeddedDisplayCoordinator: EmbeddedDisplayCoordinator,
        diagnosticsCoordinator: DiagnosticsCoordinator,
        pushToTalkSource: OnScreenPushToTalkSource,
        userProfileStore: UserProfileStore,
        audioInputSettingsStore: AudioInputSettingsStore,
        modelSettingsStore: OpenAIModelSettingsStore,
        polishPlaygroundStore: PolishPlaygroundStore,
        localWhisperModelStore: LocalWhisperModelStore,
        senseVoiceModelStore: SenseVoiceModelStore,
        memoryConstellationStore: MemoryConstellationStore,
        memoryFeatureFlagStore: MemoryFeatureFlagStore
    ) {
        self.store = HomeWindowStore(coordinator: coordinator)
        self.memoryConstellationStore = memoryConstellationStore
        self.agentMonitorCoordinator = agentMonitorCoordinator
        self.embeddedDisplayCoordinator = embeddedDisplayCoordinator
        self.diagnosticsCoordinator = diagnosticsCoordinator
        self.userProfileStore = userProfileStore
        self.modelSettingsStore = modelSettingsStore
        self.polishPlaygroundStore = polishPlaygroundStore
        self.audioInputSettingsStore = audioInputSettingsStore
        self.localWhisperModelStore = localWhisperModelStore
        self.senseVoiceModelStore = senseVoiceModelStore
        self.memoryFeatureFlagStore = memoryFeatureFlagStore
        let hostingController = NSHostingController(
            rootView: HomeWindowView(
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
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SlashVibe"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1240, height: 780))
        window.minSize = NSSize(width: 1040, height: 700)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("SlashVibeHomeWindow")
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.center()

        super.init(window: window)
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showWindowAndActivate() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
