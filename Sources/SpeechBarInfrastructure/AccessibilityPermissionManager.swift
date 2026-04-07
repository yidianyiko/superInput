import AppKit
@preconcurrency import ApplicationServices
import Foundation

public enum AccessibilityPermissionManager {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    private static let promptTracker = PromptTracker()

    public static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            guard promptTracker.consumeShouldPrompt() else {
                return AXIsProcessTrusted()
            }
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }

    @MainActor
    public static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}

private final class PromptTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var hasPrompted = false

    func consumeShouldPrompt() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if hasPrompted {
            return false
        }

        hasPrompted = true
        return true
    }
}
