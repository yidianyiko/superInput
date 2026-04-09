import Foundation
import SpeechBarInfrastructure

protocol RecordingHotkeySettingsControlling: AnyObject {
    var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot { get }
    var diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot> { get }
    func apply(_ configuration: RecordingHotkeyConfiguration)
}

extension RecordingHotkeyController: RecordingHotkeySettingsControlling {}

@MainActor
final class RecordingHotkeySettingsStore: ObservableObject, @unchecked Sendable {
    nonisolated static let defaultsKey = "recording.hotkey.configuration"

    @Published private(set) var configuration: RecordingHotkeyConfiguration
    @Published private(set) var diagnostics: RecordingHotkeyDiagnosticsSnapshot
    @Published private(set) var isCapturingCustomCombination = false
    @Published private(set) var customCombinationPreview: RecordingHotkeyCombination?

    private let defaults: UserDefaults
    private let controller: any RecordingHotkeySettingsControlling
    private var diagnosticsTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        controller: any RecordingHotkeySettingsControlling
    ) {
        self.defaults = defaults
        self.controller = controller
        let storedConfiguration = Self.loadConfiguration(from: defaults)
        self.configuration = storedConfiguration

        if controller.diagnosticsSnapshot.configuration != storedConfiguration {
            controller.apply(storedConfiguration)
        }
        self.diagnostics = controller.diagnosticsSnapshot
        bindDiagnostics()
    }

    deinit {
        diagnosticsTask?.cancel()
    }

    var effectiveCustomCombination: RecordingHotkeyCombination {
        customCombinationPreview ?? configuration.customCombination
    }

    func setMode(_ mode: RecordingHotkeyMode) {
        guard configuration.mode != mode else { return }
        saveAndApply(
            RecordingHotkeyConfiguration(
                mode: mode,
                customCombination: configuration.customCombination
            )
        )
    }

    func setCustomCombination(_ combination: RecordingHotkeyCombination) {
        guard configuration.customCombination != combination else { return }
        saveAndApply(
            RecordingHotkeyConfiguration(
                mode: configuration.mode,
                customCombination: combination
            )
        )
    }

    func beginCapturingCustomCombination() {
        isCapturingCustomCombination = true
    }

    func previewCustomCombination(_ combination: RecordingHotkeyCombination?) {
        guard isCapturingCustomCombination else { return }
        customCombinationPreview = combination
    }

    func cancelCapturingCustomCombination() {
        isCapturingCustomCombination = false
        customCombinationPreview = nil
    }

    func commitCapturedCustomCombination() {
        let preview = customCombinationPreview
        isCapturingCustomCombination = false
        customCombinationPreview = nil

        guard let preview else { return }
        setCustomCombination(preview)
    }

    nonisolated static func loadConfiguration(
        from defaults: UserDefaults = .standard
    ) -> RecordingHotkeyConfiguration {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let configuration = try? JSONDecoder().decode(RecordingHotkeyConfiguration.self, from: data)
        else {
            return .defaultRightCommand
        }
        return configuration
    }

    private func bindDiagnostics() {
        diagnosticsTask = Task { [weak self] in
            guard let self else { return }

            for await snapshot in controller.diagnosticsUpdates {
                guard !Task.isCancelled else { return }
                await self.applyDiagnostics(snapshot)
            }
        }
    }

    private func saveAndApply(_ configuration: RecordingHotkeyConfiguration) {
        self.configuration = configuration
        persist(configuration)
        controller.apply(configuration)
        diagnostics = controller.diagnosticsSnapshot
    }

    private func applyDiagnostics(_ snapshot: RecordingHotkeyDiagnosticsSnapshot) {
        diagnostics = snapshot

        guard snapshot.configuration != configuration else { return }
        configuration = snapshot.configuration
        persist(snapshot.configuration)
    }

    private func persist(_ configuration: RecordingHotkeyConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
