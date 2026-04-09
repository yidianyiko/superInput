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

public final class GlobalRightCommandPushToTalkSource: HardwareEventSource, RecordingHotkeyRuntimeSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>
    let requiresAccessibility = true

    public var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot {
        stateQueue.sync { diagnosticsSnapshotStorage }
    }

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.right-command")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installRetryTimer: Timer?
    private var isRightCommandDown = false
    private var isLeftCommandDown = false
    private var isRecordingToggledOn = false
    private var isShutdown = false
    private var diagnosticsSnapshotStorage: RecordingHotkeyDiagnosticsSnapshot

    private static let rightCommandKeyCode: CGKeyCode = 54
    private static let leftCommandKeyCode: CGKeyCode = 55
    private static let syntheticMarker: Int64 = 0x53504253
    private static let permissionGuidance = "Grant Accessibility access to use the right Command hotkey."
    private static let registrationFailureGuidance = "The right Command hotkey listener could not be installed."

    public init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        var capturedDiagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation?
        self.diagnosticsUpdates = AsyncStream { continuation in
            capturedDiagnosticsContinuation = continuation
        }
        self.diagnosticsContinuation = capturedDiagnosticsContinuation!

        let accessibilityTrusted = AXIsProcessTrusted()
        self.diagnosticsSnapshotStorage = Self.makeDiagnosticsSnapshot(
            registrationStatus: accessibilityTrusted ? .registrationFailed : .permissionRequired,
            accessibilityTrusted: accessibilityTrusted,
            guidanceText: accessibilityTrusted ? Self.registrationFailureGuidance : Self.permissionGuidance
        )
        diagnosticsContinuation.yield(diagnosticsSnapshotStorage)

        promptForAccessibilityIfNeeded()
        installEventTapIfPossible()
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        let (timer, runLoopSource, eventTap, shouldShutdown): (Timer?, CFRunLoopSource?, CFMachPort?, Bool) = stateQueue.sync {
            guard !isShutdown else {
                return (nil, nil, nil, false)
            }
            isShutdown = true

            let timer = installRetryTimer
            installRetryTimer = nil

            let runLoopSource = self.runLoopSource
            self.runLoopSource = nil

            let eventTap = self.eventTap
            self.eventTap = nil

            return (timer, runLoopSource, eventTap, true)
        }

        guard shouldShutdown else { return }

        timer?.invalidate()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        continuation.finish()
        diagnosticsContinuation.finish()
    }

    private func installEventTapIfPossible() {
        let shouldContinue = stateQueue.sync { !isShutdown }
        guard shouldContinue else { return }

        guard eventTap == nil else {
            cancelInstallRetry()
            return
        }

        guard AXIsProcessTrusted() else {
            updateDiagnostics(
                registrationStatus: .permissionRequired,
                accessibilityTrusted: false,
                guidanceText: Self.permissionGuidance
            )
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
            updateDiagnostics(
                registrationStatus: .registrationFailed,
                accessibilityTrusted: true,
                guidanceText: Self.registrationFailureGuidance
            )
            scheduleInstallRetry()
            return
        }

        self.eventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        cancelInstallRetry()
        updateDiagnostics(
            registrationStatus: .registered,
            accessibilityTrusted: true,
            guidanceText: nil
        )
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

    private func updateDiagnostics(
        registrationStatus: RecordingHotkeyRegistrationStatus,
        accessibilityTrusted: Bool,
        guidanceText: String?
    ) {
        let snapshot = Self.makeDiagnosticsSnapshot(
            registrationStatus: registrationStatus,
            accessibilityTrusted: accessibilityTrusted,
            guidanceText: guidanceText
        )

        let shouldYield = stateQueue.sync { () -> Bool in
            guard !isShutdown else { return false }
            diagnosticsSnapshotStorage = snapshot
            return true
        }
        guard shouldYield else { return }
        diagnosticsContinuation.yield(snapshot)
    }

    private static func makeDiagnosticsSnapshot(
        registrationStatus: RecordingHotkeyRegistrationStatus,
        accessibilityTrusted: Bool,
        guidanceText: String?
    ) -> RecordingHotkeyDiagnosticsSnapshot {
        RecordingHotkeyDiagnosticsSnapshot(
            configuration: .defaultRightCommand,
            registrationStatus: registrationStatus,
            requiresAccessibility: true,
            accessibilityTrusted: accessibilityTrusted,
            lastTrigger: nil,
            guidanceText: guidanceText
        )
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
            guard !isShutdown else { return }
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
