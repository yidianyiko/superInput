import AppKit
import Combine
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let menu: NSMenu
    private let homeWindowController: HomeWindowController
    private let memoryConstellationStore: MemoryConstellationStore
    private var sessionStateObservation: AnyCancellable?

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
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.menu = NSMenu()
        self.memoryConstellationStore = memoryConstellationStore
        self.homeWindowController = HomeWindowController(
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
        super.init()

        configureStatusItem()
        configurePopover(
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
        configureMenu()
        bindCoordinator(coordinator)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "SlashVibe\n右侧 Command 开始/结束录音\nCtrl+Option+J/K 测试旋钮切换"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp, .rightMouseDown])
    }

    private func configurePopover(
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
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 432, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: StatusPanelView(
                coordinator: coordinator,
                agentMonitorCoordinator: agentMonitorCoordinator,
                embeddedDisplayCoordinator: embeddedDisplayCoordinator,
                diagnosticsCoordinator: diagnosticsCoordinator,
                userProfileStore: userProfileStore,
                audioInputSettingsStore: audioInputSettingsStore,
                modelSettingsStore: modelSettingsStore,
                localWhisperModelStore: localWhisperModelStore,
                senseVoiceModelStore: senseVoiceModelStore,
                pushToTalkSource: pushToTalkSource,
                openHomeAction: { [weak self] in
                    self?.openHomeWindow()
                }
            )
            .frame(width: 432, height: 560)
        )
    }

    private func configureMenu() {
        let homeItem = NSMenuItem(
            title: "打开 SlashVibe 工作台",
            action: #selector(openHomeWindow),
            keyEquivalent: ""
        )
        homeItem.target = self
        menu.addItem(homeItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 SlashVibe",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func bindCoordinator(_ coordinator: VoiceSessionCoordinator) {
        updateStatusItemAppearance(for: coordinator.sessionState)
        sessionStateObservation = coordinator.$sessionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusItemAppearance(for: state)
                self?.handleSessionStateChange(state)
            }
    }

    private func updateStatusItemAppearance(for state: SpeechSessionState) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let description: String

        switch state {
        case .idle:
            symbolName = "mic.circle.fill"
            description = "SlashVibe idle"
        case .requestingPermission, .connecting:
            symbolName = "bolt.horizontal.circle.fill"
            description = "SlashVibe preparing"
        case .recording:
            symbolName = "waveform.circle.fill"
            description = "SlashVibe recording"
        case .finalizing:
            symbolName = "ellipsis.circle.fill"
            description = "SlashVibe finalizing"
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
            description = "SlashVibe error"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
    }

    private func handleSessionStateChange(_ state: SpeechSessionState) {
        switch state {
        case .requestingPermission, .connecting, .recording, .finalizing:
            if popover.isShown {
                popover.performClose(nil)
            }
        case .idle, .failed:
            break
        }
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent

        let isRightClick =
            event?.type == .rightMouseDown ||
            event?.type == .rightMouseUp ||
            (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            if popover.isShown {
                popover.performClose(nil)
            }
            statusItem.popUpMenu(menu)
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    @objc
    private func openHomeWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        homeWindowController.showWindowAndActivate()
    }

    func showHomeWindowForLocalModelSetupIfNeeded() {
        openHomeWindow()
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }
}
