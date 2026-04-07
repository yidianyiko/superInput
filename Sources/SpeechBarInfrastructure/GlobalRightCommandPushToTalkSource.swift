@preconcurrency import ApplicationServices
import Foundation
import SpeechBarDomain

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Hotkey] \(message)\n"
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

public final class GlobalRightCommandPushToTalkSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.right-command")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installRetryTimer: Timer?
    private var isRightCommandDown = false
    private var isLeftCommandDown = false
    private var isRecordingToggledOn = false

    private static let rightCommandKeyCode: CGKeyCode = 54
    private static let leftCommandKeyCode: CGKeyCode = 55
    private static let syntheticMarker: Int64 = 0x53504253

    public init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        promptForAccessibilityIfNeeded()
        installEventTapIfPossible()
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

        let mask = 1 << CGEventType.flagsChanged.rawValue

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("SlashVibe: failed to create right-command event tap.")
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

        let source = Unmanaged<GlobalRightCommandPushToTalkSource>
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

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == Self.leftCommandKeyCode {
            let isCommandDown = event.flags.contains(.maskCommand)
            stateQueue.sync(execute: {
                isLeftCommandDown = isCommandDown
            })
            return Unmanaged.passUnretained(event)
        }

        guard keyCode == Self.rightCommandKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let disallowedFlags = event.flags.intersection([
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskSecondaryFn
        ])
        if !disallowedFlags.isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let rightCommandIsDown = event.flags.contains(.maskCommand)

        stateQueue.sync(execute: {
            if rightCommandIsDown {
                guard !isLeftCommandDown else { return }
                guard !isRightCommandDown else { return }

                isRightCommandDown = true
                isRecordingToggledOn.toggle()
                let eventKind: HardwareEventKind = isRecordingToggledOn
                    ? .pushToTalkPressed
                    : .pushToTalkReleased
                debugLog(
                    "right command toggle -> \(isRecordingToggledOn ? "start" : "stop"), flags=\(event.flags.rawValue)"
                )
                continuation.yield(HardwareEvent(source: .globalRightCommandKey, kind: eventKind))
            } else {
                isRightCommandDown = false
            }
        })

        return Unmanaged.passUnretained(event)
    }
}
