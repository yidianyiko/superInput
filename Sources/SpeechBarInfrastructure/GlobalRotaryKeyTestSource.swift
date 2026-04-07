@preconcurrency import ApplicationServices
import Foundation
import SpeechBarDomain

private func rotaryDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Rotary] \(message)\n"
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

public final class GlobalRotaryKeyTestSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.rotary-test")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installRetryTimer: Timer?
    private var lastEmissionAt: Date?

    private static let leftArrowKeyCode: CGKeyCode = 123
    private static let rightArrowKeyCode: CGKeyCode = 124
    private static let jKeyCode: CGKeyCode = 38
    private static let kKeyCode: CGKeyCode = 40
    private static let minimumEventSpacing: TimeInterval = 0.22

    public init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        promptForAccessibilityIfNeeded()
        installEventTapIfPossible()
        rotaryDebugLog("installed keyboard rotary test source: Ctrl+Option+J/K (preferred), Ctrl+Option+Left/Right (compat)")
    }

    deinit {
        installRetryTimer?.invalidate()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private func installEventTapIfPossible() {
        guard eventTap == nil else {
            cancelInstallRetry()
            return
        }

        guard AXIsProcessTrusted() else {
            scheduleInstallRetry()
            return
        }

        let mask = 1 << CGEventType.keyDown.rawValue

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("SlashVibe: failed to create rotary-test event tap.")
            rotaryDebugLog("failed to create keyboard rotary event tap")
            scheduleInstallRetry()
            return
        }

        self.eventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        cancelInstallRetry()
    }

    private func scheduleInstallRetry() {
        guard installRetryTimer == nil else { return }
        installRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.installEventTapIfPossible()
        }
    }

    private func cancelInstallRetry() {
        installRetryTimer?.invalidate()
        installRetryTimer = nil
    }

    private func promptForAccessibilityIfNeeded() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let source = Unmanaged<GlobalRotaryKeyTestSource>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return source.handleEventTap(type: type, event: event)
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            rotaryDebugLog("ignored keyboard autorepeat")
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags.intersection([
            .maskControl,
            .maskAlternate,
            .maskCommand,
            .maskShift,
            .maskSecondaryFn
        ])

        guard flags.contains(.maskControl), flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        let disallowedFlags = flags.intersection([
            .maskCommand,
            .maskShift,
            .maskSecondaryFn
        ])
        guard disallowedFlags.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let kind: HardwareEventKind

        switch keyCode {
        case Self.leftArrowKeyCode, Self.jKeyCode:
            kind = .rotaryCounterClockwise
        case Self.rightArrowKeyCode, Self.kKeyCode:
            kind = .rotaryClockwise
        default:
            return Unmanaged.passUnretained(event)
        }

        rotaryDebugLog(
            "keyboard rotary event captured: keyCode=\(keyCode), flags=\(event.flags.rawValue), direction=\(kind == .rotaryClockwise ? "next" : "previous")"
        )

        let shouldEmit = stateQueue.sync { () -> Bool in
            let now = Date()
            if let lastEmissionAt,
               now.timeIntervalSince(lastEmissionAt) < Self.minimumEventSpacing {
                return false
            }
            self.lastEmissionAt = now
            return true
        }

        guard shouldEmit else {
            rotaryDebugLog("ignored rotary event because it arrived within debounce window")
            return Unmanaged.passUnretained(event)
        }

        continuation.yield(
            HardwareEvent(
                source: .keyboardRotaryTest,
                kind: kind
            )
        )

        return Unmanaged.passUnretained(event)
    }
}
