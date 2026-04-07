@preconcurrency import ApplicationServices
import AppKit
import Foundation
import SpeechBarDomain

private func windowSwitchDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [WindowSwitch] \(message)\n"
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

public final class SystemWindowSwitcher: WindowSwitching, @unchecked Sendable {
    private let applicationTracker: FrontmostApplicationTracker
    private let previewPublisher: (any WindowSwitchPreviewPublishing)?
    @MainActor private var activeRing: [GlobalWindowCandidate] = []
    @MainActor private var activeRingIndex: Int?
    @MainActor private var activeRingUpdatedAt: Date?
    @MainActor private var previewHideTask: Task<Void, Never>?

    private static let ringReuseWindow: TimeInterval = 2.0
    private static let previewHideDelay: Duration = .milliseconds(1200)

    public init(
        applicationTracker: FrontmostApplicationTracker,
        previewPublisher: (any WindowSwitchPreviewPublishing)? = nil
    ) {
        self.applicationTracker = applicationTracker
        self.previewPublisher = previewPublisher
    }

    public func switchWindow(direction: WindowSwitchDirection) async -> WindowSwitchOutcome {
        await switchWindowOnMain(direction: direction)
    }

    @MainActor
    private func switchWindowOnMain(direction: WindowSwitchDirection) async -> WindowSwitchOutcome {
        guard AXIsProcessTrusted() else {
            windowSwitchDebugLog("permission denied for direction=\(direction.rawValue)")
            await previewPublisher?.hideWindowSwitchPreview()
            return .permissionDenied
        }

        let freshCandidates = globalWindowCandidates()
        let candidates = resolvedRing(from: freshCandidates)
        windowSwitchDebugLog("global candidates count=\(candidates.count), direction=\(direction.rawValue)")

        guard candidates.count >= 2 else {
            windowSwitchDebugLog("not enough global candidates to switch")
            await previewPublisher?.hideWindowSwitchPreview()
            return .unavailable
        }

        let currentIndex = resolvedCurrentIndex(in: candidates) ?? 0
        let targetIndex: Int
        switch direction {
        case .next:
            targetIndex = (currentIndex + 1) % candidates.count
        case .previous:
            targetIndex = (currentIndex - 1 + candidates.count) % candidates.count
        }

        let target = candidates[targetIndex]
        windowSwitchDebugLog(
            "currentIndex=\(currentIndex), targetIndex=\(targetIndex), targetPid=\(target.processIdentifier), targetTitle=\(target.title ?? "nil")"
        )
        await publishPreview(candidates: candidates, selectedIndex: targetIndex)

        if focus(candidate: target) {
            activeRing = candidates
            activeRingIndex = targetIndex
            activeRingUpdatedAt = Date()
            windowSwitchDebugLog("switched global window to pid=\(target.processIdentifier), windowNumber=\(target.windowNumber)")
            return .switchedWindow
        }

        activeRing = []
        activeRingIndex = nil
        activeRingUpdatedAt = nil
        windowSwitchDebugLog("failed to focus target global window pid=\(target.processIdentifier)")
        return .unavailable
    }

    @MainActor
    private func publishPreview(candidates: [GlobalWindowCandidate], selectedIndex: Int) async {
        guard let previewPublisher else { return }

        let items = candidates.map(previewItem(for:))
        await previewPublisher.showWindowSwitchPreview(items: items, selectedIndex: selectedIndex)

        previewHideTask?.cancel()
        previewHideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.previewHideDelay)
            guard !Task.isCancelled else { return }
            await self?.previewPublisher?.hideWindowSwitchPreview()
        }
    }

    @MainActor
    private func previewItem(for candidate: GlobalWindowCandidate) -> WindowSwitchPreviewItem {
        let application = applicationTracker.application(processIdentifier: candidate.processIdentifier)
        let appName = application?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAppName = (appName?.isEmpty == false ? appName! : "App")
        let resolvedTitle = candidate.title?.isEmpty == false ? candidate.title! : resolvedAppName
        return WindowSwitchPreviewItem(
            id: candidate.signature,
            processIdentifier: candidate.processIdentifier,
            bundleIdentifier: application?.bundleIdentifier,
            appName: resolvedAppName,
            title: resolvedTitle
        )
    }

    @MainActor
    private func resolvedRing(from freshCandidates: [GlobalWindowCandidate]) -> [GlobalWindowCandidate] {
        guard freshCandidates.count >= 2 else {
            activeRing = freshCandidates
            activeRingIndex = freshCandidates.isEmpty ? nil : 0
            activeRingUpdatedAt = Date()
            return freshCandidates
        }

        guard
            let activeRingUpdatedAt,
            Date().timeIntervalSince(activeRingUpdatedAt) <= Self.ringReuseWindow,
            !activeRing.isEmpty
        else {
            activeRing = freshCandidates
            activeRingIndex = nil
            self.activeRingUpdatedAt = Date()
            return freshCandidates
        }

        let freshSignatures = Set(freshCandidates.map(\.signature))
        let preserved = activeRing.filter { freshSignatures.contains($0.signature) }
        let appended = freshCandidates.filter { candidate in
            !preserved.contains(where: { $0.signature == candidate.signature })
        }
        let ring = preserved + appended

        if ring.count >= 2 {
            activeRing = ring
            self.activeRingUpdatedAt = Date()
            return ring
        }

        activeRing = freshCandidates
        activeRingIndex = nil
        self.activeRingUpdatedAt = Date()
        return freshCandidates
    }

    @MainActor
    private func resolvedCurrentIndex(in candidates: [GlobalWindowCandidate]) -> Int? {
        if
            let activeRingUpdatedAt,
            Date().timeIntervalSince(activeRingUpdatedAt) <= Self.ringReuseWindow,
            let activeRingIndex,
            activeRingIndex < candidates.count
        {
            return activeRingIndex
        }

        return currentCandidateIndex(in: candidates)
    }

    @MainActor
    private func targetProcessIdentifier() -> pid_t? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            return frontmost.processIdentifier
        }

        return applicationTracker.lastExternalProcessIdentifier()
    }

    private func availableWindows(in applicationElement: AXUIElement) -> [AXUIElement] {
        guard let windows = arrayAttribute(kAXWindowsAttribute as CFString, from: applicationElement) else {
            return []
        }

        return windows.filter(isEligibleWindow(_:))
    }

    private func focusedWindow(in applicationElement: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedWindowAttribute as CFString, from: applicationElement) ??
            elementAttribute(kAXMainWindowAttribute as CFString, from: applicationElement)
    }

    @MainActor
    private func focus(candidate: GlobalWindowCandidate) -> Bool {
        _ = applicationTracker.activate(processIdentifier: candidate.processIdentifier)

        let applicationElement = AXUIElementCreateApplication(candidate.processIdentifier)
        let windows = availableWindows(in: applicationElement)
        let targetWindow =
            matchingWindow(for: candidate, in: windows) ??
            focusedWindow(in: applicationElement) ??
            windows.first

        guard let targetWindow else {
            return false
        }

        let windowFocused = focus(window: targetWindow, in: applicationElement)
        let inputFocused = focusPreferredInput(in: applicationElement, window: targetWindow)
        windowSwitchDebugLog(
            "post-switch input focus pid=\(candidate.processIdentifier), windowFocused=\(windowFocused), inputFocused=\(inputFocused)"
        )
        return windowFocused || inputFocused
    }

    private func focus(window: AXUIElement, in applicationElement: AXUIElement) -> Bool {
        let raiseStatus = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let appFocusedStatus = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            window
        )
        let appMainStatus = AXUIElementSetAttributeValue(
            applicationElement,
            kAXMainWindowAttribute as CFString,
            window
        )
        let windowMainStatus = AXUIElementSetAttributeValue(
            window,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        let windowFocusedStatus = AXUIElementSetAttributeValue(
            window,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        return raiseStatus == .success ||
            appFocusedStatus == .success ||
            appMainStatus == .success ||
            windowMainStatus == .success ||
            windowFocusedStatus == .success
    }

    @MainActor
    private func focusPreferredInput(in applicationElement: AXUIElement, window: AXUIElement) -> Bool {
        if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute as CFString, from: applicationElement),
           isEditableInput(focusedElement) {
            return true
        }

        guard let candidate = firstEditableDescendant(of: window) else {
            windowSwitchDebugLog("no editable descendant found in switched window")
            return false
        }

        let focusedStatus = AXUIElementSetAttributeValue(
            candidate,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        let appFocusedStatus = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            candidate
        )
        let pressStatus = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
        let success =
            focusedStatus == .success ||
            appFocusedStatus == .success ||
            pressStatus == .success

        windowSwitchDebugLog(
            "editable descendant focus attempt: focusedStatus=\(focusedStatus.rawValue), appFocusedStatus=\(appFocusedStatus.rawValue), pressStatus=\(pressStatus.rawValue)"
        )
        return success
    }

    @MainActor
    private func currentCandidateIndex(in candidates: [GlobalWindowCandidate]) -> Int? {
        guard let processIdentifier = targetProcessIdentifier() else { return nil }

        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        guard let currentWindow = focusedWindow(in: applicationElement) else {
            return candidates.firstIndex { $0.processIdentifier == processIdentifier }
        }

        let currentTitle = stringAttribute(kAXTitleAttribute as CFString, from: currentWindow)
        let currentFrame = frame(of: currentWindow)

        if let matchedIndex = candidates.firstIndex(where: { candidate in
            guard candidate.processIdentifier == processIdentifier else { return false }
            return candidate.matches(title: currentTitle, frame: currentFrame)
        }) {
            return matchedIndex
        }

        return candidates.firstIndex { $0.processIdentifier == processIdentifier }
    }

    @MainActor
    private func matchingWindow(
        for candidate: GlobalWindowCandidate,
        in windows: [AXUIElement]
    ) -> AXUIElement? {
        if let exactMatch = windows.first(where: { window in
            candidate.matches(
                title: stringAttribute(kAXTitleAttribute as CFString, from: window),
                frame: frame(of: window)
            )
        }) {
            return exactMatch
        }

        if let frameMatch = windows.first(where: { window in
            guard let frame = frame(of: window) else { return false }
            return candidate.matches(frame: frame)
        }) {
            return frameMatch
        }

        return windows.first
    }

    private func firstEditableDescendant(of root: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited: Set<UInt> = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let identifier = CFHash(current)
            if visited.contains(identifier) {
                continue
            }
            visited.insert(identifier)

            if isEditableInput(current) {
                return current
            }

            if let children = arrayAttribute(kAXChildrenAttribute as CFString, from: current) {
                queue.append(contentsOf: children)
            }
        }

        return nil
    }

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

    private func isEligibleWindow(_ window: AXUIElement) -> Bool {
        if let role = stringAttribute(kAXRoleAttribute as CFString, from: window),
           role != kAXWindowRole as String {
            return false
        }

        if boolAttribute(kAXMinimizedAttribute as CFString, from: window) == true {
            return false
        }

        return true
    }

    @MainActor
    private func globalWindowCandidates() -> [GlobalWindowCandidate] {
        let cgCandidates = cgWindowCandidates()
        let axCandidates = axWindowCandidates()
        windowSwitchDebugLog("cg candidates=\(cgCandidates.count), ax candidates=\(axCandidates.count)")
        if axCandidates.count >= 2 {
            return axCandidates
        }

        if !cgCandidates.isEmpty {
            return cgCandidates
        }

        return axCandidates
    }

    @MainActor
    private func cgWindowCandidates() -> [GlobalWindowCandidate] {
        guard
            let infoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return infoList.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                return nil
            }

            guard let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t else {
                return nil
            }

            if processIdentifier == getpid() {
                return nil
            }

            guard let application = applicationTracker.application(processIdentifier: processIdentifier) else {
                return nil
            }

            guard application.activationPolicy == .regular else {
                return nil
            }

            guard !application.isHidden, !application.isTerminated else {
                return nil
            }

            let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) ?? .zero
            guard bounds.width >= 140, bounds.height >= 100 else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String
            if ownerName == "Window Server" || ownerName == "Dock" {
                return nil
            }

            let windowNumber = info[kCGWindowNumber as String] as? Int ?? 0
            let title = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return GlobalWindowCandidate(
                processIdentifier: processIdentifier,
                windowNumber: windowNumber,
                title: title?.isEmpty == true ? nil : title,
                frame: bounds
            )
        }
    }

    @MainActor
    private func axWindowCandidates() -> [GlobalWindowCandidate] {
        let orderedApplications = orderedRegularApplications()
        return orderedApplications.flatMap { application in
            let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
            let windows = availableWindows(in: applicationElement)

            return windows.compactMap { window -> GlobalWindowCandidate? in
                guard let frame = frame(of: window), frame.width >= 140, frame.height >= 100 else {
                    return nil
                }

                let title = stringAttribute(kAXTitleAttribute as CFString, from: window)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return GlobalWindowCandidate(
                    processIdentifier: application.processIdentifier,
                    windowNumber: 0,
                    title: title?.isEmpty == true ? nil : title,
                    frame: frame
                )
            }
        }
    }

    @MainActor
    private func orderedRegularApplications() -> [NSRunningApplication] {
        let recent = applicationTracker.recentExternalApplications()
        let recentProcessIDs = Set(recent.map(\.processIdentifier))

        let remaining = NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular &&
                    !application.isTerminated &&
                    !application.isHidden &&
                    application.bundleIdentifier != Bundle.main.bundleIdentifier &&
                    !recentProcessIDs.contains(application.processIdentifier)
            }
            .sorted { lhs, rhs in
                (lhs.localizedName ?? "") < (rhs.localizedName ?? "")
            }

        return recent + remaining
    }

    private func elementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as! AXUIElement?
    }

    private func arrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return (value as? Bool)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard
            let positionValue = valueAttribute(kAXPositionAttribute as CFString, from: element),
            let sizeValue = valueAttribute(kAXSizeAttribute as CFString, from: element)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue) == .cgPoint else { return nil }
        guard AXValueGetType(sizeValue) == .cgSize else { return nil }
        guard AXValueGetValue(positionValue, .cgPoint, &position) else { return nil }
        guard AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }

        return CGRect(origin: position, size: size)
    }

    private func valueAttribute(_ attribute: CFString, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as! AXValue?
    }
}

private struct GlobalWindowCandidate {
    let processIdentifier: pid_t
    let windowNumber: Int
    let title: String?
    let frame: CGRect
    var signature: String {
        let titlePart = title ?? ""
        let roundedX = Int(frame.origin.x.rounded())
        let roundedY = Int(frame.origin.y.rounded())
        let roundedWidth = Int(frame.width.rounded())
        let roundedHeight = Int(frame.height.rounded())
        return "\(processIdentifier)|\(windowNumber)|\(titlePart)|\(roundedX),\(roundedY),\(roundedWidth),\(roundedHeight)"
    }

    func matches(title otherTitle: String?, frame otherFrame: CGRect?) -> Bool {
        matches(title: otherTitle) || matches(frame: otherFrame)
    }

    func matches(title otherTitle: String?) -> Bool {
        guard let title, let otherTitle else { return false }
        return title == otherTitle
    }

    func matches(frame otherFrame: CGRect?) -> Bool {
        guard let otherFrame else { return false }

        let originDelta = hypot(frame.origin.x - otherFrame.origin.x, frame.origin.y - otherFrame.origin.y)
        let widthDelta = abs(frame.width - otherFrame.width)
        let heightDelta = abs(frame.height - otherFrame.height)

        return originDelta <= 12 && widthDelta <= 16 && heightDelta <= 16
    }
}
