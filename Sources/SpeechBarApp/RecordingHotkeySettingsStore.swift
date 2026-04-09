import Carbon.HIToolbox
import Foundation
import SpeechBarInfrastructure

protocol RecordingHotkeySettingsControlling: AnyObject {
    var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot { get }
    var diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot> { get }
    func apply(_ configuration: RecordingHotkeyConfiguration)
}

extension RecordingHotkeyController: RecordingHotkeySettingsControlling {}

@MainActor
final class RecordingHotkeySettingsStore: ObservableObject, @unchecked Sendable {
    nonisolated static let defaultsKey = "recording.hotkey.configuration"

    @Published private(set) var configuration: RecordingHotkeyConfiguration
    @Published private(set) var diagnostics: RecordingHotkeyDiagnosticsSnapshot
    @Published private(set) var isCapturingCustomCombination = false
    @Published private(set) var customCombinationPreview: RecordingHotkeyCombination?

    private let defaults: UserDefaults
    private let controller: any RecordingHotkeySettingsControlling
    private var diagnosticsTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        controller: any RecordingHotkeySettingsControlling
    ) {
        self.defaults = defaults
        self.controller = controller
        let storedConfiguration = Self.loadConfiguration(from: defaults)
        self.configuration = storedConfiguration

        if controller.diagnosticsSnapshot.configuration != storedConfiguration {
            controller.apply(storedConfiguration)
        }
        self.diagnostics = controller.diagnosticsSnapshot
        bindDiagnostics()
    }

    deinit {
        diagnosticsTask?.cancel()
    }

    var effectiveCustomCombination: RecordingHotkeyCombination {
        customCombinationPreview ?? configuration.customCombination
    }

    var primaryShortcutDisplay: String {
        primaryShortcutDisplay(for: configuration)
    }

    func primaryShortcutDisplay(for configuration: RecordingHotkeyConfiguration) -> String {
        switch configuration.mode {
        case .rightCommand:
            return "右侧 Command"
        case .customCombo:
            return configuration.customCombination.displayString
        }
    }

    var primaryShortcutSymbols: [String] {
        switch configuration.mode {
        case .rightCommand:
            return ["⌘", "Right"]
        case .customCombo:
            return Self.symbols(for: effectiveCustomCombination)
        }
    }

    var homeHeroHelpText: String {
        "按\(primaryShortcutDisplay)开始或结束录音。转写、润色与写入整合为一个更安静的工作流。"
    }

    var panelHelpText: String {
        switch configuration.mode {
        case .rightCommand:
            return "右侧 Command 单击开始，再次单击结束。"
        case .customCombo:
            return "按\(primaryShortcutDisplay)开始，再按一次结束。"
        }
    }

    var recordingStopHelpText: String {
        "正在听你说话，再点一次按钮或按\(primaryShortcutDisplay)结束。"
    }

    var statusItemToolTipText: String {
        statusItemToolTipText(for: configuration)
    }

    func statusItemToolTipText(for configuration: RecordingHotkeyConfiguration) -> String {
        "SlashVibe\n\(primaryShortcutDisplay(for: configuration)) 开始/结束录音\nCtrl+Option+J/K 测试旋钮切换"
    }

    var currentHotkeyText: String {
        "当前快捷键：\(primaryShortcutDisplay)"
    }

    var registrationStatusText: String {
        diagnostics.registrationStatus.displayText
    }

    var diagnosticsDetailText: String {
        if let guidanceText = diagnostics.guidanceText, !guidanceText.isEmpty {
            return guidanceText
        }

        switch diagnostics.registrationStatus {
        case .registered:
            return diagnostics.requiresAccessibility
                ? "使用全局右侧 Command 监听，需要系统辅助功能权限保持启用。"
                : "自定义组合键已注册，录音时可在任意应用中触发。"
        case .permissionRequired:
            return "授予辅助功能权限后，全局热键才能在其他应用中生效。"
        case .invalidConfiguration:
            return "请选择至少一个修饰键，并搭配一个主键。"
        case .registrationFailed:
            return "系统未能注册当前快捷键，请尝试更换组合后重试。"
        }
    }

    var lastTriggerText: String {
        guard let lastTrigger = diagnostics.lastTrigger else {
            return "最近触发：暂无记录"
        }

        let actionText = switch lastTrigger.action {
        case .start:
            "开始录音"
        case .stop:
            "结束录音"
        }
        let timestamp = DateFormatter.localizedString(
            from: lastTrigger.occurredAt,
            dateStyle: .none,
            timeStyle: .short
        )
        return "最近触发：\(actionText) · \(timestamp)"
    }

    var customCaptureHelpText: String {
        if isCapturingCustomCombination {
            return "正在监听键盘输入。先按住修饰键，再按主键；按 Esc 取消。"
        }
        return "建议使用 Control、Option、Shift、Command 的组合，避免与系统快捷键冲突。"
    }

    func validationMessage(
        for combination: RecordingHotkeyCombination?
    ) -> String {
        guard let combination else {
            return "先按住至少一个修饰键，再按字母、数字、回车或空格。"
        }

        switch combination.validationResult {
        case .valid:
            return "松开按键后会立即保存这个组合。"
        case .missingModifier:
            return "至少需要一个修饰键，例如 Control 或 Option。"
        case .missingMainKey:
            return "继续按下一个主键来完成组合。"
        case .reservedRightCommand:
            return "右侧 Command 已保留给默认模式，请换一个主键。"
        }
    }

    func setMode(_ mode: RecordingHotkeyMode) {
        guard configuration.mode != mode else { return }
        saveAndApply(
            RecordingHotkeyConfiguration(
                mode: mode,
                customCombination: configuration.customCombination
            )
        )
    }

    func setCustomCombination(_ combination: RecordingHotkeyCombination) {
        guard configuration.customCombination != combination else { return }
        saveAndApply(
            RecordingHotkeyConfiguration(
                mode: configuration.mode,
                customCombination: combination
            )
        )
    }

    func beginCapturingCustomCombination() {
        isCapturingCustomCombination = true
    }

    func previewCustomCombination(_ combination: RecordingHotkeyCombination?) {
        guard isCapturingCustomCombination else { return }
        customCombinationPreview = combination
    }

    func cancelCapturingCustomCombination() {
        isCapturingCustomCombination = false
        customCombinationPreview = nil
    }

    func commitCapturedCustomCombination() {
        let preview = customCombinationPreview
        isCapturingCustomCombination = false
        customCombinationPreview = nil

        guard let preview else { return }
        setCustomCombination(preview)
    }

    func retryRegistration() {
        controller.apply(configuration)
        diagnostics = controller.diagnosticsSnapshot
    }

    nonisolated static func loadConfiguration(
        from defaults: UserDefaults = .standard
    ) -> RecordingHotkeyConfiguration {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let configuration = try? JSONDecoder().decode(RecordingHotkeyConfiguration.self, from: data)
        else {
            return .defaultRightCommand
        }
        return configuration
    }

    private func bindDiagnostics() {
        diagnosticsTask = Task { [weak self] in
            guard let self else { return }

            for await snapshot in controller.diagnosticsUpdates {
                guard !Task.isCancelled else { return }
                await self.applyDiagnostics(snapshot)
            }
        }
    }

    private func saveAndApply(_ configuration: RecordingHotkeyConfiguration) {
        self.configuration = configuration
        persist(configuration)
        controller.apply(configuration)
        diagnostics = controller.diagnosticsSnapshot
    }

    private func applyDiagnostics(_ snapshot: RecordingHotkeyDiagnosticsSnapshot) {
        diagnostics = snapshot

        guard snapshot.configuration != configuration else { return }
        configuration = snapshot.configuration
        persist(snapshot.configuration)
    }

    private func persist(_ configuration: RecordingHotkeyConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func symbols(for combination: RecordingHotkeyCombination) -> [String] {
        var symbols: [String] = []
        if combination.modifiers & UInt32(controlKey) != 0 {
            symbols.append("⌃")
        }
        if combination.modifiers & UInt32(optionKey) != 0 {
            symbols.append("⌥")
        }
        if combination.modifiers & UInt32(cmdKey) != 0 {
            symbols.append("⌘")
        }
        if combination.modifiers & UInt32(shiftKey) != 0 {
            symbols.append("⇧")
        }
        symbols.append(combination.keyCode.map(Self.displayString(for:)) ?? "?")
        return symbols
    }

    private static func displayString(for keyCode: UInt32) -> String {
        RecordingHotkeyCombination(keyCode: keyCode, modifiers: 0)
            .displayString
            .replacingOccurrences(of: "?", with: "")
    }
}
