import AppKit
import Carbon.HIToolbox
import Foundation
import SpeechBarDomain

public final class GlobalShortcutToggleSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.global-shortcut")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isRecordingActive = false

    private static let triggerKeyCode = UInt32(kVK_ANSI_R)
    private static let triggerModifiers = UInt32(controlKey | optionKey | cmdKey)
    private static let hotKeySignature: OSType = 0x53505348 // "SPSH"
    private static let hotKeyIdentifier: UInt32 = 1

    public init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        DispatchQueue.main.async { [weak self] in
            self?.registerHotKeyIfNeeded()
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func registerHotKeyIfNeeded() {
        guard hotKeyRef == nil, eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            NSLog("SlashVibe: failed to install global shortcut handler (\(installStatus)).")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )

        let registerStatus = RegisterEventHotKey(
            Self.triggerKeyCode,
            Self.triggerModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
                self.eventHandlerRef = nil
            }
            NSLog("SlashVibe: failed to register global shortcut (\(registerStatus)).")
            return
        }

        NSLog("SlashVibe: global shortcut registered (Control + Option + Command + R).")
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let userData, let eventRef else {
            return noErr
        }

        let source = Unmanaged<GlobalShortcutToggleSource>
            .fromOpaque(userData)
            .takeUnretainedValue()

        return source.handleHotKeyEvent(eventRef)
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard hotKeyID.signature == Self.hotKeySignature, hotKeyID.id == Self.hotKeyIdentifier else {
            return noErr
        }

        stateQueue.sync {
            isRecordingActive.toggle()
            NSLog(
                "SlashVibe: global shortcut triggered (\(isRecordingActive ? "start" : "stop"))."
            )
            continuation.yield(
                HardwareEvent(
                    source: .globalShortcut,
                    kind: isRecordingActive ? .pushToTalkPressed : .pushToTalkReleased
                )
            )
        }

        return noErr
    }
}
