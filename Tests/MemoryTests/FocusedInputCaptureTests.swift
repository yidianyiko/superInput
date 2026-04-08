import Testing
import MemoryDomain
@testable import SpeechBarInfrastructure

@Suite("Focused input capture")
struct FocusedInputCaptureTests {
    @Test
    func secureRoleIsExcludedFromPersistence() {
        let classifier = SensitiveFieldClassifier(optedOutApps: [], optedOutFieldLabels: [])
        let snapshot = FocusedInputSnapshot(
            appIdentifier: "com.apple.TextEdit",
            appName: "TextEdit",
            windowTitle: "Untitled",
            pageTitle: nil,
            fieldRole: "AXSecureTextField",
            fieldLabel: "Password",
            isEditable: true,
            isSecure: true
        )

        #expect(classifier.classify(snapshot) == .secureExcluded)
    }
}
