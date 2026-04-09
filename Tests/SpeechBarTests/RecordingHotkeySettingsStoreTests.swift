import Carbon.HIToolbox
import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarInfrastructure

@Suite("RecordingHotkeySettingsStore", .serialized)
struct RecordingHotkeySettingsStoreTests {
    @Test
    @MainActor
    func loadsPersistedConfigurationFromUserDefaults() throws {
        let defaults = makeRecordingHotkeySettingsDefaults()
        defer { clearRecordingHotkeySettingsDefaults(defaults) }

        let configuration = RecordingHotkeyConfiguration(
            mode: .customCombo,
            customCombination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_J),
                modifiers: UInt32(controlKey | optionKey)
            )
        )
        defaults.set(
            try JSONEncoder().encode(configuration),
            forKey: RecordingHotkeySettingsStore.defaultsKey
        )
        let diagnostics = makeDiagnostics(
            configuration: configuration,
            registrationStatus: .registered,
            requiresAccessibility: false
        )
        let controller = MockRecordingHotkeySettingsController(diagnosticsSnapshot: diagnostics)

        let store = RecordingHotkeySettingsStore(defaults: defaults, controller: controller)

        #expect(store.configuration == configuration)
        #expect(store.diagnostics == diagnostics)
        #expect(store.effectiveCustomCombination == configuration.customCombination)
        #expect(!store.isCapturingCustomCombination)
    }

    @Test
    @MainActor
    func changingModeAndCapturedCombinationPersistsAndReconfiguresRuntimeController() throws {
        let defaults = makeRecordingHotkeySettingsDefaults()
        defer { clearRecordingHotkeySettingsDefaults(defaults) }

        let controller = MockRecordingHotkeySettingsController(
            diagnosticsSnapshot: makeDiagnostics(
                configuration: .defaultRightCommand,
                registrationStatus: .registered,
                requiresAccessibility: true
            )
        )
        let store = RecordingHotkeySettingsStore(defaults: defaults, controller: controller)
        let capturedCombination = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey | shiftKey)
        )

        store.setMode(.customCombo)
        store.beginCapturingCustomCombination()
        store.previewCustomCombination(capturedCombination)
        store.commitCapturedCustomCombination()

        let expectedModeConfiguration = RecordingHotkeyConfiguration(
            mode: .customCombo,
            customCombination: RecordingHotkeyConfiguration.defaultRightCommand.customCombination
        )
        let expectedFinalConfiguration = RecordingHotkeyConfiguration(
            mode: .customCombo,
            customCombination: capturedCombination
        )

        #expect(controller.appliedConfigurations == [
            expectedModeConfiguration,
            expectedFinalConfiguration
        ])
        #expect(store.configuration == expectedFinalConfiguration)
        #expect(store.diagnostics.configuration == expectedFinalConfiguration)
        #expect(!store.isCapturingCustomCombination)
        #expect(store.customCombinationPreview == nil)

        let reloaded = RecordingHotkeySettingsStore(
            defaults: defaults,
            controller: MockRecordingHotkeySettingsController(
                diagnosticsSnapshot: makeDiagnostics(
                    configuration: expectedFinalConfiguration,
                    registrationStatus: .registered,
                    requiresAccessibility: false
                )
            )
        )
        #expect(reloaded.configuration == expectedFinalConfiguration)
    }

    @Test
    @MainActor
    func diagnosticsUpdatesRefreshObservableStateAndPreviewHelpers() async throws {
        let defaults = makeRecordingHotkeySettingsDefaults()
        defer { clearRecordingHotkeySettingsDefaults(defaults) }

        let controller = MockRecordingHotkeySettingsController(
            diagnosticsSnapshot: makeDiagnostics(
                configuration: .defaultRightCommand,
                registrationStatus: .registered,
                requiresAccessibility: true
            )
        )
        let store = RecordingHotkeySettingsStore(defaults: defaults, controller: controller)
        let previewCombination = RecordingHotkeyCombination(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )
        let expectedLastTrigger = RecordingHotkeyLastTrigger(
            occurredAt: Date(timeIntervalSinceReferenceDate: 123),
            mode: .rightCommand,
            action: .start
        )

        store.beginCapturingCustomCombination()
        store.previewCustomCombination(previewCombination)
        #expect(store.isCapturingCustomCombination)
        #expect(store.customCombinationPreview == previewCombination)
        #expect(store.effectiveCustomCombination == previewCombination)

        controller.emitDiagnostics(
            makeDiagnostics(
                configuration: .defaultRightCommand,
                registrationStatus: .permissionRequired,
                requiresAccessibility: true,
                accessibilityTrusted: false,
                lastTrigger: expectedLastTrigger,
                guidanceText: "Grant Accessibility access to use the right Command hotkey."
            )
        )

        try await waitForRecordingHotkeyDiagnostics(
            on: store,
            expected: makeDiagnostics(
                configuration: .defaultRightCommand,
                registrationStatus: .permissionRequired,
                requiresAccessibility: true,
                accessibilityTrusted: false,
                lastTrigger: expectedLastTrigger,
                guidanceText: "Grant Accessibility access to use the right Command hotkey."
            )
        )

        store.cancelCapturingCustomCombination()
        #expect(!store.isCapturingCustomCombination)
        #expect(store.customCombinationPreview == nil)
        #expect(store.effectiveCustomCombination == store.configuration.customCombination)
    }
}

@MainActor
private func waitForRecordingHotkeyDiagnostics(
    on store: RecordingHotkeySettingsStore,
    expected: RecordingHotkeyDiagnosticsSnapshot,
    timeout: Duration = .milliseconds(250)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if store.diagnostics == expected {
            return
        }
        await Task.yield()
    }
    Issue.record("Timed out waiting for diagnostics update.")
    throw RecordingHotkeySettingsStoreTestFailure.timeout
}

private func makeDiagnostics(
    configuration: RecordingHotkeyConfiguration,
    registrationStatus: RecordingHotkeyRegistrationStatus,
    requiresAccessibility: Bool,
    accessibilityTrusted: Bool = true,
    lastTrigger: RecordingHotkeyLastTrigger? = nil,
    guidanceText: String? = nil
) -> RecordingHotkeyDiagnosticsSnapshot {
    RecordingHotkeyDiagnosticsSnapshot(
        configuration: configuration,
        registrationStatus: registrationStatus,
        requiresAccessibility: requiresAccessibility,
        accessibilityTrusted: accessibilityTrusted,
        lastTrigger: lastTrigger,
        guidanceText: guidanceText
    )
}

private func makeRecordingHotkeySettingsDefaults() -> UserDefaults {
    let suiteName = "RecordingHotkeySettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "recordingHotkeySettingsStoreTests.suiteName")
    return defaults
}

private func clearRecordingHotkeySettingsDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "recordingHotkeySettingsStoreTests.suiteName") else { return }
    defaults.removePersistentDomain(forName: suiteName)
}

private enum RecordingHotkeySettingsStoreTestFailure: Error {
    case timeout
}
