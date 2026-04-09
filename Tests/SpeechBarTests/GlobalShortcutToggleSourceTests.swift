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
    func assignsUniqueHotkeyIdentifiersToEachInstance() {
        let firstRegistrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        _ = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: firstRegistrar
        )

        let secondRegistrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        _ = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: secondRegistrar
        )

        #expect(firstRegistrar.registeredHotKeyID != nil)
        #expect(secondRegistrar.registeredHotKeyID != nil)
        let firstHotKeyID = firstRegistrar.registeredHotKeyID ?? EventHotKeyID()
        let secondHotKeyID = secondRegistrar.registeredHotKeyID ?? EventHotKeyID()
        #expect(
            firstHotKeyID.signature != secondHotKeyID.signature ||
            firstHotKeyID.id != secondHotKeyID.id
        )
    }

    @Test
    func cleansUpAfterFailedRegistration() {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: OSStatus(eventHotKeyExistsErr))
        let source = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: registrar
        )

        #expect(source.registrationStatusForTesting() == .registrationFailed)
        #expect(registrar.installHandlerCallCount == 1)
        #expect(registrar.registerCallCount == 1)
        #expect(registrar.unregisterCallCount == 1)
        #expect(registrar.removeHandlerCallCount == 1)
    }

    @Test
    func cleansUpOnDeinit() {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        do {
            let source = GlobalShortcutToggleSource(
                combination: RecordingHotkeyCombination(
                    keyCode: UInt32(kVK_ANSI_R),
                    modifiers: UInt32(controlKey | optionKey | cmdKey)
                ),
                registrar: registrar
            )

            #expect(source.registrationStatusForTesting() == .registered)
        }

        #expect(registrar.unregisterCallCount == 1)
        #expect(registrar.removeHandlerCallCount == 1)
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

    @Test
    func routesRegisteredHandlerInvocationsBackToTheSource() {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        let source = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: registrar
        )

        #expect(registrar.registeredHotKeyID != nil)

        let hotKeyID = registrar.registeredHotKeyID ?? EventHotKeyID()
        registrar.invokeInstalledHandler(with: hotKeyID)
        registrar.invokeInstalledHandler(with: hotKeyID)

        let events = source.eventsForTesting(limit: 2)
        #expect(events.map(\.kind) == [.pushToTalkPressed, .pushToTalkReleased])
    }

    @Test
    func ignoresHotkeyEventsWithDifferentIdentifiers() {
        let registrar = MockGlobalHotKeyRegistrar(registerStatus: noErr)
        let source = GlobalShortcutToggleSource(
            combination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            ),
            registrar: registrar
        )

        #expect(registrar.registeredHotKeyID != nil)

        let registeredHotKeyID = registrar.registeredHotKeyID ?? EventHotKeyID()
        registrar.invokeInstalledHandler(
            with: EventHotKeyID(signature: registeredHotKeyID.signature, id: registeredHotKeyID.id &+ 1)
        )

        let events = source.eventsForTesting(limit: 1)
        #expect(events.isEmpty)
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
    private(set) var registeredHotKeyID: EventHotKeyID?
    private var installedHandler: EventHandlerUPP?
    private var installedUserData: UnsafeMutableRawPointer?
    private let installedEventClass = OSType(kEventClassKeyboard)
    private let installedEventKind = UInt32(kEventHotKeyPressed)

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
        installedHandler = handler
        installedUserData = userData
        return installStatus
    }

    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, hotKeyRef: inout EventHotKeyRef?) -> OSStatus {
        registerCallCount += 1
        registeredKeyCode = keyCode
        registeredModifiers = modifiers
        registeredHotKeyID = hotKeyID
        return registerStatus
    }

    func unregister(_ hotKeyRef: EventHotKeyRef?) {
        unregisterCallCount += 1
    }

    func removeHandler(_ eventHandlerRef: EventHandlerRef?) {
        removeHandlerCallCount += 1
    }

    func invokeInstalledHandler(with hotKeyID: EventHotKeyID) {
        guard let installedHandler else { return }

        var event: EventRef?
        let createStatus = CreateEvent(
            kCFAllocatorDefault,
            installedEventClass,
            installedEventKind,
            0,
            EventAttributes(kEventAttributeNone),
            &event
        )
        guard createStatus == noErr, let event else { return }
        defer { ReleaseEvent(event) }

        var hotKeyID = hotKeyID
        let setStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        guard setStatus == noErr else { return }

        _ = installedHandler(nil, event, installedUserData)
    }
}
