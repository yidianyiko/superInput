import AppKit
import Carbon.HIToolbox
import SpeechBarInfrastructure
import SwiftUI

struct RecordingHotkeySettingsCard: View {
    @ObservedObject var store: RecordingHotkeySettingsStore
    let palette: HomeWindowStore.HomeThemePalette

    private var previewCombination: RecordingHotkeyCombination? {
        store.customCombinationPreview
    }

    private var validationCombination: RecordingHotkeyCombination? {
        store.isCapturingCustomCombination
            ? previewCombination
            : store.configuration.customCombination
    }

    private var displayedCustomCombination: String {
        if store.isCapturingCustomCombination {
            return previewCombination?.displayString ?? "等待按键输入..."
        }
        return store.configuration.customCombination.displayString
    }

    private var validationMessage: String {
        if store.isCapturingCustomCombination {
            return store.validationMessage(for: validationCombination)
        }

        if store.configuration.customCombination.validationResult == .valid {
            return "当前组合有效，切换到“自定义组合”后会立即生效。"
        }

        return store.validationMessage(for: store.configuration.customCombination)
    }

    private var captureBorderColor: Color {
        guard store.isCapturingCustomCombination else { return palette.border }
        guard let previewCombination else { return palette.accent }

        switch previewCombination.validationResult {
        case .valid:
            return palette.accent
        case .missingModifier, .missingMainKey:
            return palette.highlight
        case .reservedRightCommand:
            return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("录音快捷键")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("选择默认右侧 Command，或录制一个自定义全局组合键。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(spacing: 12) {
                HotkeyModeButton(
                    title: "右侧 Command",
                    subtitle: "保持默认体验，按下开始，再按一次结束。",
                    isSelected: store.configuration.mode == .rightCommand,
                    palette: palette
                ) {
                    store.setMode(.rightCommand)
                }

                HotkeyModeButton(
                    title: "自定义组合",
                    subtitle: "使用你自己的修饰键和主键组合。",
                    isSelected: store.configuration.mode == .customCombo,
                    palette: palette
                ) {
                    store.setMode(.customCombo)
                }
            }

            HStack(spacing: 12) {
                HotkeyInfoTile(
                    title: "当前生效",
                    value: store.currentHotkeyText,
                    detail: store.registrationStatusText,
                    palette: palette
                )

                HotkeyInfoTile(
                    title: "权限状态",
                    value: store.diagnostics.requiresAccessibility
                        ? (store.diagnostics.accessibilityTrusted ? "辅助功能已授权" : "等待辅助功能授权")
                        : "当前模式不需要额外授权",
                    detail: store.lastTriggerText,
                    palette: palette
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义组合录制")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(
                            store.configuration.mode == .customCombo
                                ? "这个组合会立即用于状态栏、浮层和全局录音提示。"
                                : "先录制并保存一个组合，切换到“自定义组合”后生效。"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    Text(displayedCustomCombination)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.softFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(captureBorderColor, lineWidth: store.isCapturingCustomCombination ? 2 : 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.isCapturingCustomCombination ? "正在监听新的组合键" : "已保存的自定义组合")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textMuted)

                        Text(displayedCustomCombination)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.textPrimary)

                        Text(validationMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .frame(minHeight: 112)
                .background(
                    RecordingHotkeyCaptureView(
                        isActive: store.isCapturingCustomCombination,
                        onPreview: { store.previewCustomCombination($0) },
                        onCommit: { _ in store.commitCapturedCustomCombination() },
                        onCancel: { store.cancelCapturingCustomCombination() }
                    )
                )

                HStack(spacing: 10) {
                    Button(store.isCapturingCustomCombination ? "等待输入..." : "录制新组合") {
                        store.beginCapturingCustomCombination()
                    }
                    .buttonStyle(HotkeyPrimaryButtonStyle(palette: palette))
                    .disabled(store.isCapturingCustomCombination)

                    if store.isCapturingCustomCombination {
                        Button("取消") {
                            store.cancelCapturingCustomCombination()
                        }
                        .buttonStyle(HotkeySecondaryButtonStyle(palette: palette))
                    }

                    if store.diagnostics.requiresAccessibility && !store.diagnostics.accessibilityTrusted {
                        Button("打开辅助功能设置") {
                            AccessibilityPermissionManager.openSystemSettings()
                        }
                        .buttonStyle(HotkeySecondaryButtonStyle(palette: palette))
                    }

                    if store.diagnostics.registrationStatus == .registrationFailed {
                        Button("重新尝试注册") {
                            store.retryRegistration()
                        }
                        .buttonStyle(HotkeySecondaryButtonStyle(palette: palette))
                    }
                }

                Text(store.customCaptureHelpText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textMuted)

                Text(store.diagnosticsDetailText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [palette.cardTop, palette.cardBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct HotkeyModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let palette: HomeWindowStore.HomeThemePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.controlText : palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? palette.controlText.opacity(0.86) : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [palette.accent, palette.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(palette.softFill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.border, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HotkeyInfoTile: View {
    let title: String
    let value: String
    let detail: String
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.softFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct HotkeyPrimaryButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(
                palette.accent,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.92 : 1.0)
    }
}

private struct HotkeySecondaryButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(palette.controlText)
            .background(
                palette.controlFill,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.controlStroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1.0)
    }
}

private struct RecordingHotkeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onPreview: (RecordingHotkeyCombination?) -> Void
    let onCommit: (RecordingHotkeyCombination) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecordingHotkeyCaptureNSView {
        let view = RecordingHotkeyCaptureNSView()
        view.onPreview = onPreview
        view.onCommit = onCommit
        view.onCancel = onCancel
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: RecordingHotkeyCaptureNSView, context: Context) {
        nsView.onPreview = onPreview
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.isActive = isActive
    }
}

private final class RecordingHotkeyCaptureNSView: NSView {
    var onPreview: ((RecordingHotkeyCombination?) -> Void)?
    var onCommit: ((RecordingHotkeyCombination) -> Void)?
    var onCancel: (() -> Void)?

    var isActive = false {
        didSet {
            guard isActive else { return }
            focusIfNeeded()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        let combination = RecordingHotkeyCombination(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: event.modifierFlags)
        )
        onPreview?(combination)

        if combination.validationResult == .valid {
            onCommit?(combination)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isActive else {
            super.flagsChanged(with: event)
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        let preview = modifiers == 0
            ? nil
            : RecordingHotkeyCombination(keyCode: nil, modifiers: modifiers)
        onPreview?(preview)
    }

    private func focusIfNeeded() {
        guard isActive, let window else { return }
        DispatchQueue.main.async {
            window.makeFirstResponder(self)
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0

        if normalizedFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if normalizedFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if normalizedFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if normalizedFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        return modifiers
    }
}
