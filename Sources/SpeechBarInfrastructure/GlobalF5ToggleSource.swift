import Carbon.HIToolbox
import Foundation
import SpeechBarDomain

public protocol GlobalHotKeyRegistering {
    func installHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer?,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus
    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, hotKeyRef: inout EventHotKeyRef?) -> OSStatus
    func unregister(_ hotKeyRef: EventHotKeyRef?)
    func removeHandler(_ eventHandlerRef: EventHandlerRef?)
}

public final class GlobalShortcutToggleSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let combination: RecordingHotkeyCombination
    private let registrar: GlobalHotKeyRegistering
    private let hotKeyID: EventHotKeyID
    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private var eventHistory: [HardwareEvent] = []
    private var registrationStatus: RecordingHotkeyRegistrationStatus = .invalidConfiguration
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isRecordingActive = false

    private static let hotKeyHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let userData else {
            return noErr
        }

        let source = Unmanaged<GlobalShortcutToggleSource>
            .fromOpaque(userData)
            .takeUnretainedValue()
        guard let eventRef else {
            return noErr
        }

        source.handleHotKeyEvent(eventRef)
        return noErr
    }

    public init(
        combination: RecordingHotkeyCombination,
        registrar: GlobalHotKeyRegistering = SystemGlobalHotKeyRegistrar()
    ) {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.combination = combination
        self.registrar = registrar
        self.hotKeyID = EventHotKeyID(signature: 0x53505348, id: 1)
        self.continuation = capturedContinuation!

        guard combination.validationResult == .valid else {
            registrationStatus = .invalidConfiguration
            return
        }

        let installStatus = registrar.installHandler(
            Self.hotKeyHandler,
            userData: Unmanaged.passUnretained(self).toOpaque(),
            eventHandlerRef: &eventHandlerRef
        )

        guard installStatus == noErr else {
            registrationStatus = .registrationFailed
            return
        }

        guard let keyCode = combination.keyCode else {
            registrationStatus = .invalidConfiguration
            return
        }

        let registerStatus = registrar.register(
            keyCode: keyCode,
            modifiers: combination.modifiers,
            hotKeyID: hotKeyID,
            hotKeyRef: &hotKeyRef
        )

        guard registerStatus == noErr else {
            registrar.unregister(hotKeyRef)
            hotKeyRef = nil
            registrar.removeHandler(eventHandlerRef)
            eventHandlerRef = nil
            registrationStatus = .registrationFailed
            return
        }

        registrationStatus = .registered
    }

    deinit {
        registrar.unregister(hotKeyRef)
        registrar.removeHandler(eventHandlerRef)
    }

    func handleHotKeyPressForTesting() {
        handleHotKeyPress()
    }

    private func handleHotKeyPress() {
        isRecordingActive.toggle()
        let event = HardwareEvent(
            source: .globalShortcut,
            kind: isRecordingActive ? .pushToTalkPressed : .pushToTalkReleased
        )
        eventHistory.append(event)
        continuation.yield(event)
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) {
        guard let eventHotKeyID = Self.eventHotKeyID(from: eventRef) else {
            return
        }

        guard eventHotKeyID.signature == hotKeyID.signature, eventHotKeyID.id == hotKeyID.id else {
            return
        }

        handleHotKeyPress()
    }

    private static func eventHotKeyID(from eventRef: EventRef) -> EventHotKeyID? {
        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )

        guard status == noErr else {
            return nil
        }

        return eventHotKeyID
    }

    func registrationStatusForTesting() -> RecordingHotkeyRegistrationStatus {
        registrationStatus
    }

    func eventsForTesting(limit: Int) -> [HardwareEvent] {
        Array(eventHistory.prefix(limit))
    }
}

public struct SystemGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    public init() {}

    public func installHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer?,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    public func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, hotKeyRef: inout EventHotKeyRef?) -> OSStatus {
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregister(_ hotKeyRef: EventHotKeyRef?) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    public func removeHandler(_ eventHandlerRef: EventHandlerRef?) {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
