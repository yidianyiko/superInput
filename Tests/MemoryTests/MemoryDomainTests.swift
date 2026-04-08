import Foundation
import Testing
import MemoryDomain

@Suite("MemoryDomain smoke")
struct MemoryDomainSmokeTests {
    @Test
    func moduleLoads() {
        let request = RecallRequest(
            timestamp: Date(timeIntervalSince1970: 0),
            appIdentifier: "com.example.app",
            windowTitle: "Editor",
            pageTitle: nil,
            fieldRole: "AXTextArea",
            fieldLabel: "Body",
            requestedCapabilities: [.transcription]
        )

        #expect(request.appIdentifier == "com.example.app")
    }
}

@Suite("MemoryDomain")
struct MemoryDomainTests {
    @Test
    func observedNoChangeCountsAsConfirmedFinal() {
        let event = InputEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            languageCode: "zh",
            localeIdentifier: "zh-CN",
            appIdentifier: "com.apple.TextEdit",
            appName: "TextEdit",
            windowTitle: "Untitled",
            pageTitle: nil,
            fieldRole: "AXTextArea",
            fieldLabel: "Body",
            sensitivityClass: .normal,
            observationStatus: .observedNoChange,
            actionType: .transcribe,
            rawTranscript: "扣子空间",
            polishedText: "扣子空间",
            insertedText: "Coze Space",
            finalUserEditedText: "Coze Space",
            outcome: .published,
            durationMs: 800,
            source: .speech
        )

        #expect(event.hasConfirmedFinalText)
        #expect(event.effectiveLearningText == "Coze Space")
    }

    @Test
    func unavailableObservationLeavesInsertedTextProvisional() {
        let event = InputEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            languageCode: "en",
            localeIdentifier: "en-US",
            appIdentifier: "com.apple.TextEdit",
            appName: "TextEdit",
            windowTitle: "Untitled",
            pageTitle: nil,
            fieldRole: "AXTextArea",
            fieldLabel: "Body",
            sensitivityClass: .normal,
            observationStatus: .unavailable,
            actionType: .transcribe,
            rawTranscript: "open ai api",
            polishedText: "Open AI API",
            insertedText: "Open AI API",
            finalUserEditedText: nil,
            outcome: .published,
            durationMs: 700,
            source: .speech
        )

        #expect(!event.hasConfirmedFinalText)
        #expect(event.effectiveLearningText == "Open AI API")
        #expect(event.isProvisional)
    }
}
