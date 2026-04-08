import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryFeatureFlagStore")
struct MemoryFeatureFlagStoreTests {
    @Test
    @MainActor
    func defaultsToLearnOnlyMode() {
        let suiteName = "MemoryFeatureFlagStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MemoryFeatureFlagStore(defaults: defaults)
        #expect(store.captureEnabled)
        #expect(!store.recallEnabled)
    }
}
