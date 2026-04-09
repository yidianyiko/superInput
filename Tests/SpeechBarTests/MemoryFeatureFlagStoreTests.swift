import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryFeatureFlagStore")
struct MemoryFeatureFlagStoreTests {
    @Test
    @MainActor
    func defaultsToRecallOnMode() {
        let suiteName = "MemoryFeatureFlagStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MemoryFeatureFlagStore(defaults: defaults)
        #expect(store.captureEnabled)
        #expect(store.recallEnabled)
    }

    @Test
    @MainActor
    func defaultsToFullDisplayModeAndPersistsChanges() {
        let suiteName = "MemoryFeatureFlagStoreTests.displayMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MemoryFeatureFlagStore(defaults: defaults)
        #expect(store.displayMode == .full)

        store.displayMode = .privacySafe

        let reloaded = MemoryFeatureFlagStore(defaults: defaults)
        #expect(reloaded.displayMode == .privacySafe)
    }
}
