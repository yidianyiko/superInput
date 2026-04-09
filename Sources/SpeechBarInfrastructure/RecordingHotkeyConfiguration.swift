import Carbon.HIToolbox
import Foundation

public enum RecordingHotkeyMode: String, Codable, CaseIterable, Sendable {
    case rightCommand
    case customCombo
}

public enum RecordingHotkeyValidationResult: Sendable, Equatable {
    case valid
    case missingModifier
    case missingMainKey
    case reservedRightCommand
}

public struct RecordingHotkeyCombination: Codable, Sendable, Equatable {
    public let keyCode: UInt32?
    public let modifiers: UInt32

    public init(keyCode: UInt32?, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var validationResult: RecordingHotkeyValidationResult {
        if keyCode == UInt32(kVK_RightCommand) {
            return .reservedRightCommand
        }
        guard modifiers != 0 else { return .missingModifier }
        guard keyCode != nil else { return .missingMainKey }
        return .valid
    }

    public var displayString: String {
        let modifierDisplay = RecordingHotkeyDisplayFormatter.modifierString(for: modifiers)
        let keyDisplay = keyCode.flatMap(RecordingHotkeyDisplayFormatter.keyString(for:)) ?? "?"
        return modifierDisplay + keyDisplay
    }
}

public struct RecordingHotkeyConfiguration: Codable, Sendable, Equatable {
    public let mode: RecordingHotkeyMode
    public let customCombination: RecordingHotkeyCombination

    public init(mode: RecordingHotkeyMode, customCombination: RecordingHotkeyCombination) {
        self.mode = mode
        self.customCombination = customCombination
    }

    private static let legacyCustomCombination = RecordingHotkeyCombination(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    public static let defaultRightCommand = RecordingHotkeyConfiguration(
        mode: .rightCommand,
        customCombination: legacyCustomCombination
    )

    public static let defaultCustom = RecordingHotkeyConfiguration(
        mode: .customCombo,
        customCombination: legacyCustomCombination
    )
}

public enum RecordingHotkeyRegistrationStatus: Sendable, Equatable {
    case registered
    case permissionRequired
    case invalidConfiguration
    case registrationFailed

    public var displayText: String {
        switch self {
        case .registered:
            return "正在监听"
        case .permissionRequired:
            return "需要辅助功能权限"
        case .invalidConfiguration:
            return "快捷键无效"
        case .registrationFailed:
            return "注册失败"
        }
    }
}

public enum RecordingHotkeyTriggerAction: String, Sendable, Equatable {
    case start
    case stop
}

public struct RecordingHotkeyLastTrigger: Sendable, Equatable {
    public let occurredAt: Date
    public let mode: RecordingHotkeyMode
    public let action: RecordingHotkeyTriggerAction

    public init(occurredAt: Date, mode: RecordingHotkeyMode, action: RecordingHotkeyTriggerAction) {
        self.occurredAt = occurredAt
        self.mode = mode
        self.action = action
    }
}

public struct RecordingHotkeyDiagnosticsSnapshot: Sendable, Equatable {
    public let configuration: RecordingHotkeyConfiguration
    public let registrationStatus: RecordingHotkeyRegistrationStatus
    public let requiresAccessibility: Bool
    public let accessibilityTrusted: Bool
    public let lastTrigger: RecordingHotkeyLastTrigger?
    public let guidanceText: String?

    public init(
        configuration: RecordingHotkeyConfiguration,
        registrationStatus: RecordingHotkeyRegistrationStatus,
        requiresAccessibility: Bool,
        accessibilityTrusted: Bool,
        lastTrigger: RecordingHotkeyLastTrigger?,
        guidanceText: String?
    ) {
        self.configuration = configuration
        self.registrationStatus = registrationStatus
        self.requiresAccessibility = requiresAccessibility
        self.accessibilityTrusted = accessibilityTrusted
        self.lastTrigger = lastTrigger
        self.guidanceText = guidanceText
    }
}

enum RecordingHotkeyDisplayFormatter {
    private static let ansiDisplayStrings: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9"
    ]

    private static let specialKeyDisplayStrings: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "PgUp",
        UInt32(kVK_PageDown): "PgDn",
        UInt32(kVK_Help): "Help",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20"
    ]

    static func modifierString(for modifiers: UInt32) -> String {
        var pieces: [String] = []
        if modifiers & UInt32(controlKey) != 0 { pieces.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { pieces.append("⌥") }
        if modifiers & UInt32(cmdKey) != 0 { pieces.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { pieces.append("⇧") }
        return pieces.joined()
    }

    static func keyString(for keyCode: UInt32) -> String? {
        if let specialKeyDisplay = specialKeyDisplayStrings[keyCode] {
            return specialKeyDisplay
        }
        if let ansiDisplay = ansiDisplayStrings[keyCode] {
            return ansiDisplay
        }
        return "Key\(keyCode)"
    }
}
