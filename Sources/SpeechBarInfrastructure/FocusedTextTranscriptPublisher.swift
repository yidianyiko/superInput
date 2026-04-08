import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation
import MemoryDomain
import SpeechBarDomain

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Focus] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

public enum FocusedTextTranscriptPublisherError: LocalizedError {
    case accessibilityPermissionRequired
    case noFocusedInputTarget
    case insertionFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Transcript ready, but SlashVibe still lacks Accessibility access. Enable it in System Settings, then fully quit and reopen the app once."
        case .noFocusedInputTarget:
            return "Transcript ready, but no editable text field is focused."
        case .insertionFailed:
            return "Transcript ready, but insertion into the focused app failed."
        }
    }
}

public final class FocusedTextTranscriptPublisher: TranscriptPublisher, @unchecked Sendable {
    fileprivate static let pasteKeyCode: CGKeyCode = 9
    fileprivate static let deleteKeyCode: CGKeyCode = 51
    fileprivate static let syntheticMarker: Int64 = 0x53504253
    private static let duplicateSuppressionWindow: TimeInterval = 1.0
    private static let activationSettlingDelay: Duration = .milliseconds(80)
    private static let restoredFocusSettlingDelay: Duration = .milliseconds(40)
    private static let pasteConsumptionDelay: Duration = .milliseconds(150)
    private let applicationTracker: FrontmostApplicationTracker
    private var rememberedTarget: CapturedFocusTarget?
    private var lastSuccessfulPublish: SuccessfulPublish?
    private var activeStreamingSession: ActiveStreamingSession?

    public init(
        applicationTracker: FrontmostApplicationTracker,
        promptForAccessibilityAtLaunch: Bool = false
    ) {
        self.applicationTracker = applicationTracker
        if promptForAccessibilityAtLaunch {
            _ = AccessibilityPermissionManager.isTrusted(prompt: true)
        }
    }

    public func captureCurrentTarget() async {
        let target = await MainActor.run {
            captureFocusTarget()
        }
        await MainActor.run {
            rememberedTarget = target
        }
    }

    public func clearCapturedTarget() async {
        await MainActor.run {
            rememberedTarget = nil
        }
    }

    public func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome {
        guard !transcript.text.isEmpty else { return .publishedOnly }

        let capturedTarget = await MainActor.run {
            rememberedTarget ?? captureFocusTarget()
        }
        let fallbackProcessIdentifier = await MainActor.run {
            applicationTracker.lastExternalProcessIdentifier()
        }
        let targetProcessIdentifier = capturedTarget?.processIdentifier ?? fallbackProcessIdentifier
        let shouldSuppressDuplicate = await MainActor.run {
            isDuplicatePublish(
                text: transcript.text,
                processIdentifier: targetProcessIdentifier
            )
        }
        if shouldSuppressDuplicate {
            debugLog(
                "suppressed duplicate publish pid=\(targetProcessIdentifier ?? 0), chars=\(transcript.text.count)"
            )
            return .pasteShortcutSent
        }
        let activated = await MainActor.run {
            if let targetProcessIdentifier {
                return applicationTracker.activate(processIdentifier: targetProcessIdentifier)
            }
            return applicationTracker.activateLastExternalApplication()
        }
        if activated {
            await waitForTargetApplicationToBecomeFrontmost(processIdentifier: targetProcessIdentifier)
        }

        // Always use clipboard-based paste as the primary strategy.
        // AXUIElementSetAttributeValue reports success for many apps (especially
        // Electron / browser-based apps) but the text never actually appears.
        // Clipboard paste via simulated Cmd+V works universally.
        if await pasteIntoFocusedApplication(
            transcript.text,
            preferredTarget: capturedTarget,
            targetProcessIdentifier: targetProcessIdentifier
        ) {
            await MainActor.run {
                recordSuccessfulPublish(
                    text: transcript.text,
                    processIdentifier: targetProcessIdentifier
                )
            }
            return .pasteShortcutSent
        }

        // Fallback: try Accessibility API insertion if paste didn't work.
        if let capturedTarget,
           let element = capturedTarget.element,
           AccessibilityPermissionManager.isTrusted() {
            if await restoreFocus(to: capturedTarget),
               try await insertViaAccessibility(transcript.text, into: element) {
                await MainActor.run {
                    recordSuccessfulPublish(
                        text: transcript.text,
                        processIdentifier: targetProcessIdentifier
                    )
                }
                return .insertedIntoFocusedApp
            }
        }

        if let targetProcessIdentifier, AccessibilityPermissionManager.isTrusted() {
            if try await insertViaAccessibility(
                transcript.text,
                processIdentifier: targetProcessIdentifier
            ) {
                await MainActor.run {
                    recordSuccessfulPublish(
                        text: transcript.text,
                        processIdentifier: targetProcessIdentifier
                    )
                }
                return .insertedIntoFocusedApp
            }
        }

        if !AccessibilityPermissionManager.isTrusted() {
            return .copiedToClipboard
        }

        if targetProcessIdentifier == nil {
            return .copiedToClipboard
        }

        throw FocusedTextTranscriptPublisherError.insertionFailed
    }

    public func beginStreamingSession() async {
        let target = await MainActor.run {
            rememberedTarget ?? captureFocusTarget()
        }
        let fallbackProcessIdentifier = await MainActor.run {
            applicationTracker.lastExternalProcessIdentifier()
        }
        let processIdentifier = target?.processIdentifier ?? fallbackProcessIdentifier

        if let processIdentifier {
            let activated = await MainActor.run {
                applicationTracker.activate(processIdentifier: processIdentifier)
            }
            if activated {
                await waitForTargetApplicationToBecomeFrontmost(processIdentifier: processIdentifier)
            }
        }

        await MainActor.run {
            activeStreamingSession = ActiveStreamingSession(
                target: target,
                processIdentifier: processIdentifier,
                committedText: ""
            )
        }
    }

    public func updateStreamingTranscript(_ text: String) async throws -> TranscriptDeliveryOutcome {
        let normalized = Self.normalizeStreamingText(text)
        guard !normalized.isEmpty else {
            return .publishedOnly
        }

        let session = await MainActor.run {
            if let activeStreamingSession {
                return activeStreamingSession
            }
            let target = rememberedTarget ?? captureFocusTarget()
            let fallbackProcessIdentifier = applicationTracker.lastExternalProcessIdentifier()
            let createdSession = ActiveStreamingSession(
                target: target,
                processIdentifier: target?.processIdentifier ?? fallbackProcessIdentifier,
                committedText: ""
            )
            activeStreamingSession = createdSession
            return createdSession
        }

        let oldCharacters = Array(session.committedText)
        let newCharacters = Array(normalized)
        var prefixLength = 0
        while prefixLength < oldCharacters.count,
              prefixLength < newCharacters.count,
              oldCharacters[prefixLength] == newCharacters[prefixLength] {
            prefixLength += 1
        }

        let deleteCount = oldCharacters.count - prefixLength
        let suffix = String(newCharacters.dropFirst(prefixLength))

        guard deleteCount > 0 || !suffix.isEmpty else {
            return .publishedOnly
        }

        let preferredTarget = session.target
        let processIdentifier = session.processIdentifier
        let activated = await MainActor.run {
            if let processIdentifier {
                return applicationTracker.activate(processIdentifier: processIdentifier)
            }
            return applicationTracker.activateLastExternalApplication()
        }
        if activated {
            await waitForTargetApplicationToBecomeFrontmost(processIdentifier: processIdentifier)
        }

        if let preferredTarget {
            let restored = await MainActor.run {
                restoreFocus(to: preferredTarget)
            }
            debugLog("streaming restoreFocus result = \(restored), pid = \(preferredTarget.processIdentifier)")
            if restored {
                try? await Task.sleep(for: Self.restoredFocusSettlingDelay)
            }
        }

        if deleteCount > 0 {
            guard await MainActor.run(body: {
                postDeleteBackward(count: deleteCount, processIdentifier: processIdentifier)
            }) else {
                throw FocusedTextTranscriptPublisherError.insertionFailed
            }
        }

        let outcome: TranscriptDeliveryOutcome
        if suffix.isEmpty {
            outcome = .typedIntoFocusedApp
        } else if await pasteIntoFocusedApplication(
            suffix,
            preferredTarget: preferredTarget,
            targetProcessIdentifier: processIdentifier
        ) {
            outcome = .typedIntoFocusedApp
        } else {
            throw FocusedTextTranscriptPublisherError.insertionFailed
        }

        await MainActor.run {
            activeStreamingSession = ActiveStreamingSession(
                target: preferredTarget,
                processIdentifier: processIdentifier,
                committedText: normalized
            )
        }
        return outcome
    }

    public func finishStreamingSession(finalText: String) async throws -> TranscriptDeliveryOutcome {
        let normalized = Self.normalizeStreamingText(finalText)
        defer {
            Task { @MainActor in
                self.activeStreamingSession = nil
            }
        }

        guard !normalized.isEmpty else {
            return .publishedOnly
        }
        return try await updateStreamingTranscript(normalized)
    }

    public func cancelStreamingSession() async {
        await MainActor.run {
            activeStreamingSession = nil
        }
    }

    @MainActor
    private func insertViaAccessibility(_ text: String, processIdentifier: pid_t) throws -> Bool {
        guard let focusedElement = focusedElement(processIdentifier: processIdentifier) else {
            throw FocusedTextTranscriptPublisherError.noFocusedInputTarget
        }

        return try insertViaAccessibility(text, into: focusedElement)
    }

    @MainActor
    private func insertViaAccessibility(_ text: String, into focusedElement: AXUIElement) throws -> Bool {
        if let currentValue = stringValue(for: focusedElement),
           let selectedRange = selectedRange(for: focusedElement) {
            let nsValue = currentValue as NSString
            let boundedLocation = min(selectedRange.location, nsValue.length)
            let boundedLength = min(selectedRange.length, nsValue.length - boundedLocation)
            let boundedRange = NSRange(location: boundedLocation, length: boundedLength)
            let updatedValue = nsValue.replacingCharacters(in: boundedRange, with: text)

            guard AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                updatedValue as CFTypeRef
            ) == .success else {
                return false
            }

            setInsertionPoint(
                on: focusedElement,
                location: boundedLocation + (text as NSString).length
            )
            return true
        }

        if let currentValue = stringValue(for: focusedElement) {
            let updatedValue = currentValue + text
            let status = AXUIElementSetAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                updatedValue as CFTypeRef
            )
            if status == .success {
                setInsertionPoint(
                    on: focusedElement,
                    location: (updatedValue as NSString).length
                )
                return true
            }
        }

        return false
    }

    @MainActor
    private func pasteIntoFocusedApplication(
        _ text: String,
        preferredTarget: CapturedFocusTarget?,
        targetProcessIdentifier: pid_t?
    ) async -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        await waitForModifierKeysToBeReleased()

        // Give the target app a moment to fully activate and accept input.
        try? await Task.sleep(for: Self.activationSettlingDelay)

        if let preferredTarget {
            let restored = restoreFocus(to: preferredTarget)
            debugLog("restoreFocus result = \(restored), pid = \(preferredTarget.processIdentifier)")
            if restored {
                try? await Task.sleep(for: Self.restoredFocusSettlingDelay)
            }
        }

        var pasted = postPasteShortcut()
        debugLog("session-wide CGEvent paste shortcut posted, result = \(pasted)")

        // Fallback to targeted keyboard posting only when the global paste path
        // is unavailable.
        if !pasted,
           let processIdentifier = preferredTarget?.processIdentifier ?? targetProcessIdentifier,
           postTargetedPasteShortcut(processIdentifier: processIdentifier) {
            debugLog("targeted paste shortcut posted to pid \(processIdentifier)")
            pasted = true
        }

        if pasted {
            // Wait for the target app to consume the paste.
            try? await Task.sleep(for: Self.pasteConsumptionDelay)
        }

        return pasted
    }

    @MainActor
    private func isDuplicatePublish(text: String, processIdentifier: pid_t?) -> Bool {
        guard let lastSuccessfulPublish else { return false }
        guard lastSuccessfulPublish.text == text else { return false }
        guard lastSuccessfulPublish.processIdentifier == processIdentifier else { return false }

        return Date().timeIntervalSince(lastSuccessfulPublish.occurredAt) <= Self.duplicateSuppressionWindow
    }

    @MainActor
    private func recordSuccessfulPublish(text: String, processIdentifier: pid_t?) {
        lastSuccessfulPublish = SuccessfulPublish(
            text: text,
            processIdentifier: processIdentifier,
            occurredAt: Date()
        )
    }

    @MainActor
    private func captureFocusTarget() -> CapturedFocusTarget? {
        if let target = systemWideCaptureFocusTarget() {
            return target
        }

        guard let processIdentifier = applicationTracker.lastExternalProcessIdentifier() else {
            debugLog("captureFocusTarget: no last external pid")
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let element = focusedElement(processIdentifier: processIdentifier)
        let windowElement = element.flatMap(windowElement(for:))
        let bundleIdentifier = applicationTracker.application(processIdentifier: processIdentifier)?.bundleIdentifier ?? "unknown"
        let capturedTarget = CapturedFocusTarget(
            processIdentifier: processIdentifier,
            applicationElement: applicationElement,
            windowElement: windowElement,
            element: element
        )
        debugLog(
            "captureFocusTarget(app): pid=\(processIdentifier), bundle=\(bundleIdentifier), hasElement=\(element != nil), hasWindow=\(windowElement != nil)"
        )
        return capturedTarget
    }

    @MainActor
    private func systemWideCaptureFocusTarget() -> CapturedFocusTarget? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedStatus == .success, let focusedValue else {
            debugLog("captureFocusTarget(system): focused element status = \(focusedStatus.rawValue)")
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        var processIdentifier: pid_t = 0
        let pidStatus = AXUIElementGetPid(focusedElement, &processIdentifier)
        guard pidStatus == .success, processIdentifier != 0 else {
            debugLog("captureFocusTarget(system): pid status = \(pidStatus.rawValue)")
            return nil
        }

        if applicationTracker.application(processIdentifier: processIdentifier)?.bundleIdentifier == Bundle.main.bundleIdentifier {
            debugLog("captureFocusTarget(system): focused element belongs to self app, ignoring")
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let windowElement = windowElement(for: focusedElement)
        let bundleIdentifier = applicationTracker.application(processIdentifier: processIdentifier)?.bundleIdentifier ?? "unknown"
        let capturedTarget = CapturedFocusTarget(
            processIdentifier: processIdentifier,
            applicationElement: applicationElement,
            windowElement: windowElement,
            element: focusedElement
        )
        debugLog(
            "captureFocusTarget(system): pid=\(processIdentifier), bundle=\(bundleIdentifier), hasWindow=\(windowElement != nil)"
        )
        return capturedTarget
    }

    @MainActor
    private func focusedElement(processIdentifier: pid_t) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard status == .success else { return nil }
        return (focusedValue as! AXUIElement)
    }

    @MainActor
    private func stringValue(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard status == .success else { return nil }
        return value as? String
    }

    @MainActor
    private func selectedRange(for element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard status == .success, let value else {
            return nil
        }
        let axValue = value as! AXValue

        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    @MainActor
    private func setInsertionPoint(on element: AXUIElement, location: Int) {
        var range = CFRange(location: location, length: 0)
        guard let axValue = AXValueCreate(.cfRange, &range) else { return }
        _ = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axValue
        )
    }

    @MainActor
    private func restoreFocus(to target: CapturedFocusTarget) -> Bool {
        var restored = false

        if applicationTracker.activate(processIdentifier: target.processIdentifier) {
            restored = true
        }

        let frontmostStatus = AXUIElementSetAttributeValue(
            target.applicationElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        if frontmostStatus == .success {
            restored = true
        }

        if let windowElement = target.windowElement {
            let raiseStatus = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
            if raiseStatus == .success {
                restored = true
            }

            let mainStatus = AXUIElementSetAttributeValue(
                windowElement,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            if mainStatus == .success {
                restored = true
            }

            let focusedWindowStatus = AXUIElementSetAttributeValue(
                target.applicationElement,
                kAXFocusedWindowAttribute as CFString,
                windowElement
            )
            if focusedWindowStatus == .success {
                restored = true
            }
        }

        if let element = target.element {
            let pressStatus = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if pressStatus == .success {
                restored = true
            }

            let focusedStatus = AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if focusedStatus == .success {
                restored = true
            }

            let focusedElementStatus = AXUIElementSetAttributeValue(
                target.applicationElement,
                kAXFocusedUIElementAttribute as CFString,
                element
            )
            if focusedElementStatus == .success {
                restored = true
            }

            if isFocused(element, processIdentifier: target.processIdentifier) {
                return true
            }
        }

        return restored
    }

    @MainActor
    private func windowElement(for element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &value
        )

        guard status == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    @MainActor
    private func isFocused(_ element: AXUIElement, processIdentifier: pid_t) -> Bool {
        guard let currentFocusedElement = focusedElement(processIdentifier: processIdentifier) else {
            return false
        }

        return CFEqual(currentFocusedElement, element)
    }

    @MainActor
    private func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        // Post only once. Posting to multiple taps can make some apps consume
        // the same Cmd+V more than once, which is why duplicate / triplicate
        // pastes were happening.
        return postPasteShortcutOnTap(with: source, tap: .cghidEventTap)
    }

    @MainActor
    private func postTargetedPasteShortcut(processIdentifier: pid_t) -> Bool {
        guard let postKeyboardEvent = loadAXPostKeyboardEvent() else {
            debugLog("AXUIElementPostKeyboardEvent unavailable for pid \(processIdentifier)")
            return false
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let commandDown = postKeyboardEvent(
            applicationElement,
            0,
            CGKeyCode(kVK_Command),
            DarwinBoolean(true)
        )
        let vDown = postKeyboardEvent(
            applicationElement,
            118,
            Self.pasteKeyCode,
            DarwinBoolean(true)
        )
        let vUp = postKeyboardEvent(
            applicationElement,
            118,
            Self.pasteKeyCode,
            DarwinBoolean(false)
        )
        let commandUp = postKeyboardEvent(
            applicationElement,
            0,
            CGKeyCode(kVK_Command),
            DarwinBoolean(false)
        )
        debugLog(
            "targeted paste statuses pid=\(processIdentifier), commandDown=\(commandDown.rawValue), vDown=\(vDown.rawValue), vUp=\(vUp.rawValue), commandUp=\(commandUp.rawValue)"
        )

        return commandDown == .success &&
            vDown == .success &&
            vUp == .success &&
            commandUp == .success
    }

    private func waitForTargetApplicationToBecomeFrontmost(processIdentifier: pid_t?) async {
        guard let processIdentifier else {
            try? await Task.sleep(for: .milliseconds(300))
            return
        }

        for _ in 0..<10 {
            let isFrontmost = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
            }
            if isFrontmost {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    private func waitForModifierKeysToBeReleased() async {
        for _ in 0..<75 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let blockingFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
            if !flags.intersection(blockingFlags).isEmpty {
                try? await Task.sleep(for: .milliseconds(40))
                continue
            }
            debugLog("modifier keys released before paste")
            return
        }
        debugLog("modifier keys still active when paste timeout elapsed")
    }

    @MainActor
<<<<<<< HEAD
    private func snapshot(for target: CapturedFocusTarget) -> FocusedInputSnapshot? {
        guard let element = target.element else {
            return nil
        }

        let application = applicationTracker.application(processIdentifier: target.processIdentifier)
        let appIdentifier = application?.bundleIdentifier ?? "unknown"
        let appName = application?.localizedName ?? appIdentifier
        let windowTitle = target.windowElement.flatMap { stringAttribute(kAXTitleAttribute as CFString, from: $0) }
        let fieldRole = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "AXUnknown"
        let fieldLabel = fieldLabel(for: element)

        return FocusedInputSnapshot(
            appIdentifier: appIdentifier,
            appName: appName,
            windowTitle: windowTitle,
            pageTitle: nil,
            fieldRole: fieldRole,
            fieldLabel: fieldLabel,
            isEditable: isEditableInput(element),
            isSecure: isSecureInput(element, role: fieldRole, label: fieldLabel)
        )
    }

    @MainActor
    private func fieldLabel(for element: AXUIElement) -> String? {
        let attributes: [CFString] = [
            kAXDescriptionAttribute as CFString,
            kAXTitleAttribute as CFString,
            "AXPlaceholderValue" as CFString,
            "AXHelp" as CFString
        ]

        for attribute in attributes {
            guard let value = stringAttribute(attribute, from: element)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return value
        }

        return nil
    }

    @MainActor
    private func isEditableInput(_ element: AXUIElement) -> Bool {
        if boolAttribute(kAXEnabledAttribute as CFString, from: element) == false {
            return false
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? ""
        let editable = boolAttribute("AXEditable" as CFString, from: element) ?? false

        if editable {
            return true
        }

        let acceptedRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ]

        if acceptedRoles.contains(role) {
            return true
        }

        if role == kAXGroupRole as String && subrole.lowercased().contains("text") {
            return true
        }

        return false
    }

    @MainActor
    private func isSecureInput(_ element: AXUIElement, role: String, label: String?) -> Bool {
        if role.lowercased().contains("secure") || role.lowercased().contains("password") {
            return true
        }

        if boolAttribute("AXProtectedContent" as CFString, from: element) == true {
            return true
        }

        guard let label = label?.lowercased() else {
            return false
        }

        let secureKeywords = ["password", "passcode", "token", "otp", "验证码", "密码", "口令"]
        return secureKeywords.contains { label.contains($0) }
    }

    @MainActor
    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    @MainActor
    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }

        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    @MainActor
    private func frame(for element: AXUIElement) -> CGRect? {
        guard
            let origin = pointAttribute(kAXPositionAttribute as CFString, from: element),
            let size = sizeAttribute(kAXSizeAttribute as CFString, from: element)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    @MainActor
    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    @MainActor
    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    @MainActor
    private func transcriptInjectionTargetSnapshot(
        for target: CapturedFocusTarget
    ) -> TranscriptInjectionTargetSnapshot? {
        let application = applicationTracker.application(processIdentifier: target.processIdentifier)
        let appIdentifier = application?.bundleIdentifier ?? "unknown"
        let appName = application?.localizedName ?? appIdentifier
        let elementFrame = target.element.flatMap(frame(for:))
        let windowFrame = target.windowElement.flatMap(frame(for:))
        guard let resolvedGeometry = TranscriptInjectionTargetResolver.resolve(
            elementFrame: elementFrame,
            windowFrame: windowFrame,
            screenFrames: NSScreen.screens.map(\.frame)
        ) else {
            return nil
        }

        return TranscriptInjectionTargetSnapshot(
            processIdentifier: target.processIdentifier,
            appIdentifier: appIdentifier,
            appName: appName,
            screenFrame: resolvedGeometry.screenFrame,
            windowFrame: windowFrame,
            elementFrame: elementFrame,
            destinationPoint: resolvedGeometry.destinationPoint
        )
=======
    private func postDeleteBackward(count: Int, processIdentifier: pid_t?) -> Bool {
        guard count > 0 else { return true }

        var posted = false
        if let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState) {
            for _ in 0..<count {
                guard
                    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.deleteKeyCode, keyDown: true),
                    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.deleteKeyCode, keyDown: false)
                else {
                    return false
                }
                keyDown.setIntegerValueField(CGEventField.eventSourceUserData, value: Self.syntheticMarker)
                keyUp.setIntegerValueField(CGEventField.eventSourceUserData, value: Self.syntheticMarker)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            posted = true
        }

        if posted {
            return true
        }

        guard let processIdentifier,
              let postKeyboardEvent = loadAXPostKeyboardEvent()
        else {
            return false
        }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        for _ in 0..<count {
            let down = postKeyboardEvent(
                applicationElement,
                127,
                Self.deleteKeyCode,
                DarwinBoolean(true)
            )
            let up = postKeyboardEvent(
                applicationElement,
                127,
                Self.deleteKeyCode,
                DarwinBoolean(false)
            )
            if down != .success || up != .success {
                return false
            }
        }
        return true
    }

    private static func normalizeStreamingText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
>>>>>>> 5fe97d2 (Day 0408 & First Word detect)
    }

}

extension FocusedTextTranscriptPublisher: StreamingTranscriptPublisher {}
extension FocusedTextTranscriptPublisher: TranscriptTargetCapturing {}
extension FocusedTextTranscriptPublisher: FocusedInputSnapshotProviding {
    public func currentFocusedInputSnapshot() async -> FocusedInputSnapshot? {
        let target = await MainActor.run {
            rememberedTarget ?? captureFocusTarget()
        }
        guard let target else {
            return nil
        }
        return await MainActor.run {
            snapshot(for: target)
        }
    }

    public func observedTextAfterPublish() async -> String? {
        await MainActor.run {
            let target = rememberedTarget ?? captureFocusTarget()
            if let element = target?.element, let value = stringValue(for: element) {
                return value
            }

            guard let processIdentifier = target?.processIdentifier ?? applicationTracker.lastExternalProcessIdentifier(),
                  let element = focusedElement(processIdentifier: processIdentifier) else {
                return nil
            }
            return stringValue(for: element)
        }
    }
}

extension FocusedTextTranscriptPublisher: TranscriptInjectionTargetSnapshotProviding {
    public func currentTranscriptInjectionTargetSnapshot() async -> TranscriptInjectionTargetSnapshot? {
        let target = await MainActor.run {
            rememberedTarget ?? captureFocusTarget()
        }
        guard let target else {
            return nil
        }
        return await MainActor.run {
            transcriptInjectionTargetSnapshot(for: target)
        }
    }
}

private final class CapturedFocusTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    let applicationElement: AXUIElement
    let windowElement: AXUIElement?
    let element: AXUIElement?

    init(
        processIdentifier: pid_t,
        applicationElement: AXUIElement,
        windowElement: AXUIElement?,
        element: AXUIElement?
    ) {
        self.processIdentifier = processIdentifier
        self.applicationElement = applicationElement
        self.windowElement = windowElement
        self.element = element
    }
}

@MainActor
private struct SuccessfulPublish {
    let text: String
    let processIdentifier: pid_t?
    let occurredAt: Date
}

@MainActor
private struct ActiveStreamingSession {
    let target: CapturedFocusTarget?
    let processIdentifier: pid_t?
    let committedText: String
}

private typealias AXPostKeyboardEventFunction =
    @convention(c) (AXUIElement, CGCharCode, CGKeyCode, DarwinBoolean) -> AXError

private func loadAXPostKeyboardEvent() -> AXPostKeyboardEventFunction? {
    let applicationServicesHandle = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_NOW
    )

    guard let symbol = dlsym(applicationServicesHandle, "AXUIElementPostKeyboardEvent") else {
        return nil
    }

    return unsafeBitCast(symbol, to: AXPostKeyboardEventFunction.self)
}


@MainActor
private func postPasteShortcutOnTap(
    with source: CGEventSource,
    tap: CGEventTapLocation
) -> Bool {
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: FocusedTextTranscriptPublisher.pasteKeyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: FocusedTextTranscriptPublisher.pasteKeyCode, keyDown: false)

    guard let keyDown, let keyUp else {
        return false
    }

    keyDown.flags = CGEventFlags.maskCommand
    keyUp.flags = CGEventFlags.maskCommand
    keyDown.setIntegerValueField(CGEventField.eventSourceUserData, value: FocusedTextTranscriptPublisher.syntheticMarker)
    keyUp.setIntegerValueField(CGEventField.eventSourceUserData, value: FocusedTextTranscriptPublisher.syntheticMarker)
    keyDown.post(tap: tap)
    keyUp.post(tap: tap)
    return true
}
