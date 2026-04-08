import Foundation
import Testing
import MemoryDomain
@testable import MemoryExtraction

@Suite("MemoryExtraction")
struct MemoryExtractionTests {
    @Test
    func confirmedRewriteCreatesCorrectionMemory() async throws {
        let extractor = DefaultMemoryExtractor()
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
            observationStatus: .observedFinal,
            actionType: .transcribe,
            rawTranscript: "扣子空间",
            polishedText: "扣子空间",
            insertedText: "扣子空间",
            finalUserEditedText: "Coze Space",
            outcome: .published,
            durationMs: 900,
            source: .speech
        )

        let memories = try await extractor.extract(from: event)
        #expect(memories.contains { $0.type == .correction })
    }

    @Test
    func caseOnlyRewriteStillCreatesCorrectionMemory() async throws {
        let extractor = DefaultMemoryExtractor()
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
            observationStatus: .observedFinal,
            actionType: .transcribe,
            rawTranscript: "hello world",
            polishedText: "hello world",
            insertedText: "hello world",
            finalUserEditedText: "Hello World",
            outcome: .published,
            durationMs: 900,
            source: .speech
        )

        let memories = try await extractor.extract(from: event)
        #expect(memories.contains { $0.type == .correction })
    }

    @Test
    func unavailableObservationKeepsConfidenceBelowRecallThreshold() async throws {
        let extractor = DefaultMemoryExtractor()
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
            durationMs: 900,
            source: .speech
        )

        let memories = try await extractor.extract(from: event)
        #expect(memories.allSatisfy { $0.confidence <= 0.55 })
    }

    @Test
    func transcribeEventCreatesStyleMemory() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            rawTranscript: "reply shortly",
            insertedText: "reply shortly",
            finalUserEditedText: "reply shortly"
        )

        let memories = try await extractor.extract(from: event)

        let style = try #require(memories.first { $0.type == .style })
        #expect(style.valueFingerprint == "brevity=short")
        #expect(style.scope == .app("com.apple.TextEdit"))
        #expect(style.confidence == 0.65)
    }
}

private func makeEvent(
    appIdentifier: String = "com.apple.TextEdit",
    appName: String = "TextEdit",
    windowTitle: String? = "Untitled",
    pageTitle: String? = nil,
    fieldRole: String = "AXTextArea",
    fieldLabel: String? = "Body",
    sensitivityClass: SensitivityClass = .normal,
    observationStatus: ObservationStatus = .observedFinal,
    actionType: MemoryActionType = .transcribe,
    rawTranscript: String? = "hello world",
    polishedText: String? = nil,
    insertedText: String? = "hello world",
    finalUserEditedText: String? = "hello world"
) -> InputEvent {
    InputEvent(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 0),
        languageCode: "en",
        localeIdentifier: "en-US",
        appIdentifier: appIdentifier,
        appName: appName,
        windowTitle: windowTitle,
        pageTitle: pageTitle,
        fieldRole: fieldRole,
        fieldLabel: fieldLabel,
        sensitivityClass: sensitivityClass,
        observationStatus: observationStatus,
        actionType: actionType,
        rawTranscript: rawTranscript,
        polishedText: polishedText,
        insertedText: insertedText,
        finalUserEditedText: finalUserEditedText,
        outcome: .published,
        durationMs: 900,
        source: .speech
    )
}
