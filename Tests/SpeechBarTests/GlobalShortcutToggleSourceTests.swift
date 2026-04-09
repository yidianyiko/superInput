import Carbon.HIToolbox
import Testing
@testable import SpeechBarInfrastructure
import SpeechBarDomain

@Suite("GlobalShortcutToggleSource")
struct GlobalShortcutToggleSourceTests {
    @Test
    func reportsRegistrationFailureWhenRegistrarRejectsCombination() async {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: OSStatus(eventHotKeyExistsErr))
        let source = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: registrar
        )

        let status = source.registrationStatusForTesting()
        #expect(status == .registrationFailed)
    }

    @Test
    func togglesPressedAndReleasedForRepeatedHotkeyMatches() async {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        let source = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: registrar
        )

        source.handleHotKeyPressForTesting()
        source.handleHotKeyPressForTesting()

        let events = source.eventsForTesting(limit: 2)
        #expect(events.map(\.kind) == [.pushToTalkPressed, .pushToTalkReleased])
    }
}

final class MockGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var installStatus: OSStatus
    let registerStatus: OSStatus
    private(set) var installHandlerCallCount = 0
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var removeHandlerCallCount = 0
    private(set) var registeredKeyCode: UInt32?
    private(set) var registeredModifiers: UInt32?

    init(installStatus: OSStatus = noErr, registerStatus: OSStatus) {
        self.installStatus = installStatus
        self.registerStatus = registerStatus
    }

    func installHandler(
        _ handler: EventHandlerUPP,
        userData: UnsafeMutableRawPointer?,
        eventHandlerRef: inout EventHandlerRef?
    ) -> OSStatus {
        installHandlerCallCount += 1
        return installStatus
    }

    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, hotKeyRef: inout EventHotKeyRef?) -> OSStatus {
        registerCallCount += 1
        registeredKeyCode = keyCode
        registeredModifiers = modifiers
        return registerStatus
    }

    func unregister(_ hotKeyRef: EventHotKeyRef?) {
        unregisterCallCount += 1
    }

    func removeHandler(_ eventHandlerRef: EventHandlerRef?) {
        removeHandlerCallCount += 1
    }
}
