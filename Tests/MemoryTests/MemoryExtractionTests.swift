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

    @Test
    func pageTitleFallbackCreatesSceneMemoryWithoutFieldLabel() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Reply",
            pageTitle: "Inbox Thread",
            fieldLabel: nil,
            rawTranscript: "reply soon",
            insertedText: "reply soon",
            finalUserEditedText: "reply soon"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.mail:inbox thread")
        #expect(scene.valueFingerprint == "Inbox Thread")
        #expect(scene.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Reply",
            fieldRole: "AXTextArea",
            fieldLabel: nil
        ))
    }

    @Test
    func windowTitleFallbackCreatesSceneMemoryWhenPageTitleMissing() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Draft Reply",
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "ship tomorrow",
            insertedText: "ship tomorrow",
            finalUserEditedText: "ship tomorrow"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.mail:draft reply")
        #expect(scene.valueFingerprint == "Draft Reply")
        #expect(scene.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Draft Reply",
            fieldRole: "AXTextArea",
            fieldLabel: nil
        ))
    }

    @Test
    func appNameFallbackCreatesAppScopedSceneMemoryWhenNoOtherContextExists() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.notes",
            appName: "Notes",
            windowTitle: nil,
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "buy milk",
            insertedText: "buy milk",
            finalUserEditedText: "buy milk"
        )

        let memories = try await extractor.extract(from: event)

        let scene = try #require(memories.first { $0.type == .scene })
        #expect(scene.key == "scene:com.apple.notes:notes")
        #expect(scene.valueFingerprint == "Notes")
        #expect(scene.scope == .app("com.apple.notes"))
    }

    @Test
    func sparseMetadataTranscribeEventProducesAllFourMemoryTypes() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: "Draft Reply",
            pageTitle: nil,
            fieldLabel: nil,
            rawTranscript: "open ai roadmap",
            insertedText: "open ai roadmap",
            finalUserEditedText: "OpenAI roadmap"
        )

        let memories = try await extractor.extract(from: event)

        #expect(memories.count == 4)
        #expect(Set(memories.map(\.type)) == [.correction, .vocabulary, .scene, .style])
    }

    @Test
    func secureExcludedEventStillProducesNoMemories() async throws {
        let extractor = DefaultMemoryExtractor()
        let event = makeEvent(
            appIdentifier: "com.1password.1password",
            appName: "1Password",
            windowTitle: "Sign In",
            fieldRole: "AXSecureTextField",
            fieldLabel: "Password",
            sensitivityClass: .secureExcluded,
            observationStatus: .blockedSensitive,
            rawTranscript: nil,
            insertedText: nil,
            finalUserEditedText: nil
        )

        let memories = try await extractor.extract(from: event)

        #expect(memories.isEmpty)
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
