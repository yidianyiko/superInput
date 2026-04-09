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

    public static let defaultCustom = RecordingHotkeyConfiguration(
        mode: .customCombo,
        customCombination: RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )
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
    static func modifierString(for modifiers: UInt32) -> String {
        var pieces: [String] = []
        if modifiers & UInt32(controlKey) != 0 { pieces.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { pieces.append("⌥") }
        if modifiers & UInt32(cmdKey) != 0 { pieces.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { pieces.append("⇧") }
        return pieces.joined()
    }

    static func keyString(for keyCode: UInt32) -> String? {
        switch keyCode {
        case UInt32(kVK_ANSI_R):
            return "R"
        case UInt32(kVK_Return):
            return "↩"
        case UInt32(kVK_Space):
            return "Space"
        default:
            return nil
        }
    }
}
