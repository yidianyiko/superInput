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

        let status = await source.registrationStatusForTesting()
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

        let events = await source.eventsForTesting(limit: 2)
        #expect(events.map(\.kind) == [.pushToTalkPressed, .pushToTalkReleased])
    }
}

final class MockGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    let registerStatus: OSStatus

    init(registerStatus: OSStatus) {
        self.registerStatus = registerStatus
    }

    func installHandler(_ handler: EventHandlerUPP, userData: UnsafeMutableRawPointer?) -> OSStatus {
        noErr
    }

    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, hotKeyRef: inout EventHotKeyRef?) -> OSStatus {
        registerStatus
    }

    func unregister(_ hotKeyRef: EventHotKeyRef?) {}

    func removeHandler(_ eventHandlerRef: EventHandlerRef?) {}
}
