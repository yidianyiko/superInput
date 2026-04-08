import AppKit
import SpeechBarApplication
import SpeechBarInfrastructure
import SwiftUI

@MainActor
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private enum ActivationMode {
        case accessory
        case regular
    }

    private let store: HomeWindowStore
    private let agentMonitorCoordinator: AgentMonitorCoordinator
    private let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    private let diagnosticsCoordinator: DiagnosticsCoordinator
    private let userProfileStore: UserProfileStore
    private let modelSettingsStore: OpenAIModelSettingsStore
    private let audioInputSettingsStore: AudioInputSettingsStore
    private let localWhisperModelStore: LocalWhisperModelStore
    private let senseVoiceModelStore: SenseVoiceModelStore

    init(
        coordinator: VoiceSessionCoordinator,
        agentMonitorCoordinator: AgentMonitorCoordinator,
        embeddedDisplayCoordinator: EmbeddedDisplayCoordinator,
        diagnosticsCoordinator: DiagnosticsCoordinator,
        pushToTalkSource: OnScreenPushToTalkSource,
        userProfileStore: UserProfileStore,
        audioInputSettingsStore: AudioInputSettingsStore,
        modelSettingsStore: OpenAIModelSettingsStore,
        localWhisperModelStore: LocalWhisperModelStore,
        senseVoiceModelStore: SenseVoiceModelStore
    ) {
        self.store = HomeWindowStore(coordinator: coordinator)
        self.agentMonitorCoordinator = agentMonitorCoordinator
        self.embeddedDisplayCoordinator = embeddedDisplayCoordinator
        self.diagnosticsCoordinator = diagnosticsCoordinator
        self.userProfileStore = userProfileStore
        self.modelSettingsStore = modelSettingsStore
        self.audioInputSettingsStore = audioInputSettingsStore
        self.localWhisperModelStore = localWhisperModelStore
        self.senseVoiceModelStore = senseVoiceModelStore
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
                localWhisperModelStore: localWhisperModelStore,
                senseVoiceModelStore: senseVoiceModelStore,
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
        applyActivationMode(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        applyActivationMode(.accessory)
    }

    private func applyActivationMode(_ mode: ActivationMode) {
        let policy: NSApplication.ActivationPolicy = switch mode {
        case .accessory:
            .accessory
        case .regular:
            .regular
        }

        guard NSApp.activationPolicy() != policy else { return }
        _ = NSApp.setActivationPolicy(policy)
    }
}
