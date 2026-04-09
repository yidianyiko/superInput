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

protocol GlobalRightCommandRetryTimer: AnyObject, Sendable {
    func invalidate()
}

private final class FoundationGlobalRightCommandRetryTimer: GlobalRightCommandRetryTimer, @unchecked Sendable {
    private let timer: Timer

    init(action: @escaping @Sendable () -> Void) {
        self.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            action()
        }
    }

    func invalidate() {
        timer.invalidate()
    }
}

public final class GlobalRightCommandPushToTalkSource: HardwareEventSource, RecordingHotkeyRuntimeSource, @unchecked Sendable {
    struct Dependencies {
        let isAccessibilityTrusted: @Sendable () -> Bool
        let promptForAccessibilityIfNeeded: @Sendable () -> Void
        let createEventTap: @Sendable (CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
        let makeRunLoopSource: @Sendable (CFMachPort) -> CFRunLoopSource
        let addRunLoopSource: @Sendable (CFRunLoopSource) -> Void
        let removeRunLoopSource: @Sendable (CFRunLoopSource) -> Void
        let enableEventTap: @Sendable (CFMachPort) -> Void
        let invalidateEventTap: @Sendable (CFMachPort) -> Void
        let createRetryTimer: @Sendable (@escaping @Sendable () -> Void) -> any GlobalRightCommandRetryTimer

        static let live = Dependencies(
            isAccessibilityTrusted: {
                AXIsProcessTrusted()
            },
            promptForAccessibilityIfNeeded: {
                let options = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            },
            createEventTap: { callback, userInfo in
                let mask = 1 << CGEventType.flagsChanged.rawValue
                return CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: CGEventMask(mask),
                    callback: callback,
                    userInfo: userInfo
                )
            },
            makeRunLoopSource: { eventTap in
                CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            },
            addRunLoopSource: { runLoopSource in
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            },
            removeRunLoopSource: { runLoopSource in
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            },
            enableEventTap: { eventTap in
                CGEvent.tapEnable(tap: eventTap, enable: true)
            },
            invalidateEventTap: { eventTap in
                CFMachPortInvalidate(eventTap)
            },
            createRetryTimer: { action in
                FoundationGlobalRightCommandRetryTimer(action: action)
            }
        )
    }

    public let events: AsyncStream<HardwareEvent>
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>
    let requiresAccessibility = true

    public var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot {
        stateQueue.sync { diagnosticsSnapshotStorage }
    }

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation
    private let dependencies: Dependencies
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.right-command")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installRetryTimer: (any GlobalRightCommandRetryTimer)?
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

    public convenience init() {
        self.init(dependencies: .live)
    }

    init(dependencies: Dependencies) {
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
        self.dependencies = dependencies

        self.diagnosticsSnapshotStorage = Self.makeDiagnosticsSnapshot(
            registrationStatus: .permissionRequired,
            accessibilityTrusted: false,
            guidanceText: Self.permissionGuidance
        )

        dependencies.promptForAccessibilityIfNeeded()
        installEventTapIfPossible(emitDiagnostics: false)
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        let (timer, runLoopSource, eventTap, shouldShutdown): ((any GlobalRightCommandRetryTimer)?, CFRunLoopSource?, CFMachPort?, Bool) = stateQueue.sync {
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
            dependencies.removeRunLoopSource(runLoopSource)
        }

        if let eventTap {
            dependencies.invalidateEventTap(eventTap)
        }

        continuation.finish()
        diagnosticsContinuation.finish()
    }

    private func installEventTapIfPossible(emitDiagnostics: Bool = true) {
        let shouldAttemptInstall = stateQueue.sync { () -> Bool in
            guard !isShutdown else { return false }
            return eventTap == nil
        }
        guard shouldAttemptInstall else {
            cancelInstallRetry()
            return
        }

        guard dependencies.isAccessibilityTrusted() else {
            updateDiagnostics(
                registrationStatus: .permissionRequired,
                accessibilityTrusted: false,
                guidanceText: Self.permissionGuidance,
                emitDiagnostics: emitDiagnostics
            )
            scheduleInstallRetry()
            return
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = dependencies.createEventTap(Self.eventTapCallback, userInfo) else {
            NSLog("SlashVibe: failed to create right-command event tap.")
            updateDiagnostics(
                registrationStatus: .registrationFailed,
                accessibilityTrusted: true,
                guidanceText: Self.registrationFailureGuidance,
                emitDiagnostics: emitDiagnostics
            )
            scheduleInstallRetry()
            return
        }

        let runLoopSource = dependencies.makeRunLoopSource(eventTap)
        let installResult = stateQueue.sync { () -> (installed: Bool, timer: (any GlobalRightCommandRetryTimer)?) in
            guard !isShutdown, self.eventTap == nil else {
                return (false, nil)
            }

            self.eventTap = eventTap
            self.runLoopSource = runLoopSource
            let timer = installRetryTimer
            installRetryTimer = nil
            self.dependencies.addRunLoopSource(runLoopSource)
            self.dependencies.enableEventTap(eventTap)
            return (true, timer)
        }
        guard installResult.installed else {
            dependencies.invalidateEventTap(eventTap)
            return
        }

        installResult.timer?.invalidate()
        updateDiagnostics(
            registrationStatus: .registered,
            accessibilityTrusted: true,
            guidanceText: nil,
            emitDiagnostics: emitDiagnostics
        )
    }

    private func scheduleInstallRetry() {
        stateQueue.sync {
            guard !isShutdown, installRetryTimer == nil else { return }
            installRetryTimer = dependencies.createRetryTimer { [weak self] in
                self?.installEventTapIfPossible()
            }
        }
    }

    private func cancelInstallRetry() {
        let timer = stateQueue.sync { () -> (any GlobalRightCommandRetryTimer)? in
            let timer = installRetryTimer
            installRetryTimer = nil
            return timer
        }
        timer?.invalidate()
    }

    private func updateDiagnostics(
        registrationStatus: RecordingHotkeyRegistrationStatus,
        accessibilityTrusted: Bool,
        guidanceText: String?,
        emitDiagnostics: Bool = true
    ) {
        let snapshot = Self.makeDiagnosticsSnapshot(
            registrationStatus: registrationStatus,
            accessibilityTrusted: accessibilityTrusted,
            guidanceText: guidanceText
        )

        let shouldYield = stateQueue.sync { () -> Bool in
            guard !isShutdown else { return false }
            let didChange = diagnosticsSnapshotStorage != snapshot
            diagnosticsSnapshotStorage = snapshot
            return emitDiagnostics && didChange
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
                dependencies.enableEventTap(eventTap)
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
