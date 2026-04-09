import Carbon.HIToolbox
import Testing
@testable import SpeechBarInfrastructure

@Suite("RecordingHotkeyConfiguration")
struct RecordingHotkeyConfigurationTests {
    @Test
    func formatsModifierComboForDisplay() {
        let combination = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        #expect(combination.validationResult == .valid)
        #expect(combination.displayString == "⌘⇧R")
    }

    @Test
    func formatsAlphabeticKeysForDisplay() {
        let combination = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey)
        )

        #expect(combination.validationResult == .valid)
        #expect(combination.displayString == "⌘A")
    }

    @Test
    func formatsDigitKeysForDisplay() {
        let combination = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey)
        )

        #expect(combination.validationResult == .valid)
        #expect(combination.displayString == "⌥1")
    }

    @Test
    func rejectsBareKeysAndModifierOnlyCombinations() {
        let bareKey = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: 0
        )
        let modifierOnly = RecordingHotkeyCombination(
            keyCode: nil,
            modifiers: UInt32(cmdKey)
        )

        #expect(bareKey.validationResult == .missingModifier)
        #expect(modifierOnly.validationResult == .missingMainKey)
    }

    @Test
    func rejectsReservedRightCommandCombination() {
        let reservedRightCommand = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_RightCommand),
            modifiers: 0
        )

        #expect(reservedRightCommand.validationResult == .reservedRightCommand)
    }

    @Test
    func defaultCustomConfigurationUsesLegacyModifierCombo() {
        let configuration = RecordingHotkeyConfiguration.defaultCustom

        #expect(configuration.mode == .customCombo)
        #expect(configuration.customCombination.displayString == "⌃⌥⌘R")
    }

    @Test
    func defaultRightCommandConfigurationUsesStartupMode() {
        let configuration = RecordingHotkeyConfiguration.defaultRightCommand

        #expect(configuration.mode == .rightCommand)
        #expect(configuration.customCombination.displayString == "⌃⌥⌘R")
    }
}
