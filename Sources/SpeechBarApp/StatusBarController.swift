import AppKit
import Combine
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import SwiftUI

@MainActor
protocol HomeWindowControlling: AnyObject {
    func showWindowAndActivate()
}

extension HomeWindowController: HomeWindowControlling {}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let menu: NSMenu
    private let themeDefaults: UserDefaults
    private let homeWindowControllerFactory: () -> any HomeWindowControlling
    private var homeWindowController: (any HomeWindowControlling)?
    private var sessionStateObservation: AnyCancellable?

    init(
        coordinator: VoiceSessionCoordinator,
        agentMonitorCoordinator: AgentMonitorCoordinator,
        embeddedDisplayCoordinator: EmbeddedDisplayCoordinator,
        diagnosticsCoordinator: DiagnosticsCoordinator,
        pushToTalkSource: OnScreenPushToTalkSource,
        userProfileStore: UserProfileStore,
        audioInputSettingsStore: AudioInputSettingsStore,
        recordingHotkeySettingsStore: RecordingHotkeySettingsStore,
        modelSettingsStore: OpenAIModelSettingsStore,
        polishPlaygroundStore: PolishPlaygroundStore,
        localWhisperModelStore: LocalWhisperModelStore,
        senseVoiceModelStore: SenseVoiceModelStore,
        memoryConstellationStore: MemoryConstellationStore,
        memoryFeatureFlagStore: MemoryFeatureFlagStore,
        themeDefaults: UserDefaults = .standard,
        homeWindowControllerFactory: (() -> any HomeWindowControlling)? = nil
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.menu = NSMenu()
        self.themeDefaults = themeDefaults
        self.homeWindowControllerFactory = homeWindowControllerFactory ?? {
            HomeWindowController(
                coordinator: coordinator,
                agentMonitorCoordinator: agentMonitorCoordinator,
                embeddedDisplayCoordinator: embeddedDisplayCoordinator,
                diagnosticsCoordinator: diagnosticsCoordinator,
                pushToTalkSource: pushToTalkSource,
                userProfileStore: userProfileStore,
                audioInputSettingsStore: audioInputSettingsStore,
                recordingHotkeySettingsStore: recordingHotkeySettingsStore,
                modelSettingsStore: modelSettingsStore,
                polishPlaygroundStore: polishPlaygroundStore,
                localWhisperModelStore: localWhisperModelStore,
                senseVoiceModelStore: senseVoiceModelStore,
                memoryConstellationStore: memoryConstellationStore,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            )
        }
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
            recordingHotkeySettingsStore: recordingHotkeySettingsStore,
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
        recordingHotkeySettingsStore: RecordingHotkeySettingsStore,
        modelSettingsStore: OpenAIModelSettingsStore,
        localWhisperModelStore: LocalWhisperModelStore,
        senseVoiceModelStore: SenseVoiceModelStore
    ) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 432, height: 560)
        let hostingController = NSHostingController(
            rootView: StatusPanelView(
                coordinator: coordinator,
                agentMonitorCoordinator: agentMonitorCoordinator,
                embeddedDisplayCoordinator: embeddedDisplayCoordinator,
                diagnosticsCoordinator: diagnosticsCoordinator,
                userProfileStore: userProfileStore,
                audioInputSettingsStore: audioInputSettingsStore,
                recordingHotkeySettingsStore: recordingHotkeySettingsStore,
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
        popover.contentViewController = hostingController
        updatePopoverAppearance()
    }

    var popoverAppearanceNameForTesting: NSAppearance.Name? {
        popover.contentViewController?.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    }

    private func updatePopoverAppearance() {
        let appearanceName: NSAppearance.Name = currentThemePreset().palette.isDark ? .darkAqua : .aqua
        popover.contentViewController?.view.appearance = NSAppearance(named: appearanceName)
    }

    private func currentThemePreset() -> HomeWindowStore.ThemePreset {
        guard
            let rawValue = themeDefaults.string(forKey: "home.selectedTheme"),
            let preset = HomeWindowStore.ThemePreset(rawValue: rawValue)
        else {
            return .green
        }
        return preset
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
            updatePopoverAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    @objc
    private func openHomeWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        let homeWindowController = resolvedHomeWindowController()
        homeWindowController.showWindowAndActivate()
    }

    func showHomeWindowForLocalModelSetupIfNeeded() {
        openHomeWindow()
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func resolvedHomeWindowController() -> any HomeWindowControlling {
        if let homeWindowController {
            return homeWindowController
        }

        let homeWindowController = homeWindowControllerFactory()
        self.homeWindowController = homeWindowController
        return homeWindowController
    }
}
