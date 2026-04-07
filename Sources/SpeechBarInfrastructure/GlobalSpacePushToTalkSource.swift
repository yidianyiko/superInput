@preconcurrency import ApplicationServices
import Foundation
import SpeechBarDomain

public final class GlobalSpacePushToTalkSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.global-space")
    private let activationDelay: TimeInterval

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingActivation: DispatchWorkItem?
    private var isSpaceDown = false
    private var isPushToTalkActive = false

    private static let spaceKeyCode: Int64 = 49
    private static let syntheticMarker: Int64 = 0x53504252

    public init(activationDelay: TimeInterval = 0.18) {
        self.activationDelay = activationDelay

        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        promptForAccessibilityIfNeeded()
        installEventTap()
    }

    deinit {
        pendingActivation?.cancel()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    private func installEventTap() {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.eventTap = eventTap

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func promptForAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let source = Unmanaged<GlobalSpacePushToTalkSource>
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

        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.spaceKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = event.flags.intersection([
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskSecondaryFn
        ])
        guard modifiers.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let shouldSuppress = stateQueue.sync { () -> Bool in
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return true
                }
                if isSpaceDown {
                    return true
                }

                isSpaceDown = true
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    guard self.isSpaceDown, !self.isPushToTalkActive else { return }
                    self.isPushToTalkActive = true
                    self.continuation.yield(
                        HardwareEvent(source: .globalSpaceKey, kind: .pushToTalkPressed)
                    )
                }
                pendingActivation = workItem
                stateQueue.asyncAfter(deadline: .now() + activationDelay, execute: workItem)
                return true
            }

            return shouldSuppress ? nil : Unmanaged.passUnretained(event)

        case .keyUp:
            let shouldSuppress = stateQueue.sync { () -> Bool in
                pendingActivation?.cancel()
                pendingActivation = nil

                let wasActive = isPushToTalkActive
                isSpaceDown = false
                isPushToTalkActive = false

                if wasActive {
                    continuation.yield(
                        HardwareEvent(source: .globalSpaceKey, kind: .pushToTalkReleased)
                    )
                } else {
                    postSyntheticSpacePress()
                }
                return true
            }

            return shouldSuppress ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func postSyntheticSpacePress() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(Self.spaceKeyCode), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(Self.spaceKeyCode), keyDown: false)

        keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
