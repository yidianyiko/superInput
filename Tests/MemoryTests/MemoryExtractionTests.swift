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
}
