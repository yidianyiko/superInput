import Foundation
import Testing
import MemoryDomain
import MemoryExtraction
@testable import MemoryStorageSQLite

@Suite("MemoryStorageSQLite")
struct MemoryStorageSQLiteTests {
    @Test
    func secureEventsPersistNoText() async throws {
        let store = try makeTestStore()
        let event = InputEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            languageCode: "en",
            localeIdentifier: "en-US",
            appIdentifier: "com.1password.1password",
            appName: "1Password",
            windowTitle: "Sign In",
            pageTitle: nil,
            fieldRole: "AXSecureTextField",
            fieldLabel: "Password",
            sensitivityClass: .secureExcluded,
            observationStatus: .blockedSensitive,
            actionType: .transcribe,
            rawTranscript: nil,
            polishedText: nil,
            insertedText: nil,
            finalUserEditedText: nil,
            outcome: .skippedSensitive,
            durationMs: 0,
            source: .speech
        )

        try await store.insert(event: event)
        let snapshot = try await store.debugFetchEvent(id: event.id)
        #expect(snapshot.rawTranscript == nil)
        #expect(snapshot.insertedText == nil)
    }

    @Test
    func expiredEventsArePurgedByRetentionPolicy() async throws {
        let store = try makeTestStore(now: Date(timeIntervalSince1970: 40 * 24 * 60 * 60))
        try await store.insert(event: staleObservedEvent())
        try await store.compactExpiredEvents()
        #expect(try await store.debugEventCount() == 0)
    }

    @Test
    func memoriesRoundTripForMatchingRequest() async throws {
        let store = try makeTestStore()
        let memory = MemoryItem(
            id: UUID(),
            type: .correction,
            key: "corr:test",
            valuePayload: Data("preferred=field".utf8),
            valueFingerprint: "preferred=field",
            identityHash: "corr:test",
            scope: .field(
                appIdentifier: "com.apple.mail",
                windowTitle: "Reply",
                fieldRole: "AXTextArea",
                fieldLabel: "Message Body"
            ),
            confidence: 0.8,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            lastConfirmedAt: Date(timeIntervalSince1970: 0),
            sourceEventIDs: []
        )

        try await store.upsert(memory: memory)
        let memories = try await store.listMemories(
            for: RecallRequest(
                timestamp: Date(timeIntervalSince1970: 1),
                appIdentifier: "com.apple.mail",
                windowTitle: "Reply",
                pageTitle: nil,
                fieldRole: "AXTextArea",
                fieldLabel: "Message Body",
                requestedCapabilities: [.polish]
            )
        )

        #expect(memories.count == 1)
        #expect(String(data: memories[0].valuePayload, encoding: .utf8) == "preferred=field")
    }

    @Test
    func distinctFieldScopesDoNotOverwriteEachOther() async throws {
        let store = try makeTestStore()
        let extractor = DefaultMemoryExtractor()

        let replySceneMemory = try await extractor.extract(from: observedEvent(windowTitle: "Reply"))
            .first { $0.type == .scene }
        let draftSceneMemory = try await extractor.extract(from: observedEvent(windowTitle: "Draft"))
            .first { $0.type == .scene }

        #expect(replySceneMemory != nil)
        #expect(draftSceneMemory != nil)

        try await store.upsert(memory: try #require(replySceneMemory))
        try await store.upsert(memory: try #require(draftSceneMemory))

        let replyMemories = try await store.listMemories(for: recallRequest(windowTitle: "Reply"))
        let draftMemories = try await store.listMemories(for: recallRequest(windowTitle: "Draft"))

        #expect(replyMemories.contains { $0.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Reply",
            fieldRole: "AXTextArea",
            fieldLabel: "Message Body"
        ) })
        #expect(draftMemories.contains { $0.scope == .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Draft",
            fieldRole: "AXTextArea",
            fieldLabel: "Message Body"
        ) })
    }

    private func makeTestStore(now: Date = Date(timeIntervalSince1970: 0)) throws -> MemoryStorageSQLiteStore {
        try MemoryStorageSQLiteStore(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite"),
            keyProvider: StaticMemoryKeyProvider(),
            now: { now }
        )
    }

    private func staleObservedEvent() -> InputEvent {
        InputEvent(
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
            rawTranscript: "hello",
            polishedText: "hello",
            insertedText: "hello",
            finalUserEditedText: "hello",
            outcome: .published,
            durationMs: 500,
            source: .speech
        )
    }

    private func observedEvent(windowTitle: String) -> InputEvent {
        InputEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            languageCode: "en",
            localeIdentifier: "en-US",
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            windowTitle: windowTitle,
            pageTitle: nil,
            fieldRole: "AXTextArea",
            fieldLabel: "Message Body",
            sensitivityClass: .normal,
            observationStatus: .observedFinal,
            actionType: .transcribe,
            rawTranscript: "reply soon",
            polishedText: "reply soon",
            insertedText: "reply soon",
            finalUserEditedText: "reply soon",
            outcome: .published,
            durationMs: 500,
            source: .speech
        )
    }

    private func recallRequest(windowTitle: String) -> RecallRequest {
        RecallRequest(
            timestamp: Date(timeIntervalSince1970: 1),
            appIdentifier: "com.apple.mail",
            windowTitle: windowTitle,
            pageTitle: nil,
            fieldRole: "AXTextArea",
            fieldLabel: "Message Body",
            requestedCapabilities: [.polish]
        )
    }
}

private struct StaticMemoryKeyProvider: MemoryKeyProviding {
    func loadOrCreateMasterKey() throws -> Data {
        Data(repeating: 0x2A, count: 32)
    }
}
