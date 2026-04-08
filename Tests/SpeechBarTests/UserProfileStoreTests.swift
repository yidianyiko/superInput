import Foundation
import Testing
@testable import SpeechBarApp

@Suite("UserProfileStore")
struct UserProfileStoreTests {
    @Test
    @MainActor
    func applyingReplyDemoSeedPackLoadsDemoPersona() {
        let suiteName = "UserProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserProfileStore(defaults: defaults)
        store.applyReplyDemoSeedPack()

        #expect(store.polishMode == .reply)
        #expect(store.profession == "AI 创业者")
        #expect(store.memoryProfile.contains("偏好：结论先行"))
        #expect(store.memoryProfile.contains("偏好：自然一点，不要太正式"))
        #expect(store.terminologyGlossary.map(\.term).contains("Redheak"))
        #expect(store.terminologyGlossary.map(\.term).contains("Demo Day"))
        #expect(store.terminologyStatusMessage == "已载入 Demo Seed Pack。")
    }
}
