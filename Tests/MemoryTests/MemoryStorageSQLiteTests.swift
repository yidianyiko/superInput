import Foundation
import Testing
import MemoryDomain
import MemoryExtraction
import SQLite3
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

    @Test
    func catalogQueryFiltersByStatusAndType() async throws {
        let store = try makeTestStore()

        try await store.upsert(memory: MemoryItem(
            id: UUID(),
            type: .vocabulary,
            key: "term:openai",
            valuePayload: Data("OpenAI".utf8),
            valueFingerprint: "OpenAI",
            identityHash: "active-vocabulary",
            scope: .app("com.apple.mail"),
            confidence: 0.80,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            lastConfirmedAt: Date(timeIntervalSince1970: 0),
            sourceEventIDs: []
        ))

        try await store.upsert(memory: MemoryItem(
            id: UUID(),
            type: .scene,
            key: "scene:mail:body",
            valuePayload: Data("AXTextArea".utf8),
            valueFingerprint: "AXTextArea",
            identityHash: "deleted-scene",
            scope: .field(
                appIdentifier: "com.apple.mail",
                windowTitle: "Reply",
                fieldRole: "AXTextArea",
                fieldLabel: "Message Body"
            ),
            confidence: 0.55,
            status: .deleted,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            lastConfirmedAt: nil,
            sourceEventIDs: []
        ))

        let rows = try await store.listMemories(
            matching: MemoryCenterQuery(
                statuses: [.active],
                types: [.vocabulary]
            )
        )

        #expect(rows.count == 1)
        #expect(rows[0].type == .vocabulary)
        #expect(rows[0].valueFingerprint == "OpenAI")
    }

    @Test
    func hiddenMemoriesAreExcludedFromDefaultCatalogButRemainQueryable() async throws {
        let store = try makeTestStore()
        let memory = MemoryItem(
            id: UUID(),
            type: .vocabulary,
            key: "term:hidden-openai",
            valuePayload: Data("OpenAI".utf8),
            valueFingerprint: "OpenAI",
            identityHash: "hidden-openai",
            scope: .app("com.apple.mail"),
            confidence: 0.80,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            lastConfirmedAt: Date(timeIntervalSince1970: 0),
            sourceEventIDs: []
        )

        try await store.upsert(memory: memory)
        try await store.markHidden(identityHash: memory.identityHash, hiddenAt: Date(timeIntervalSince1970: 2))

        let activeRows = try await store.listMemories(matching: MemoryCenterQuery())
        let hiddenRows = try await store.listMemories(
            matching: MemoryCenterQuery(statuses: [.hidden], types: [.vocabulary])
        )

        #expect(activeRows.isEmpty)
        #expect(hiddenRows.count == 1)
        #expect(hiddenRows[0].status == .hidden)
    }

    @Test
    func catalogQueryIgnoresCorruptRowsOutsideRequestedFilters() async throws {
        let context = try makeTestStoreContext()

        try await context.store.upsert(memory: MemoryItem(
            id: UUID(),
            type: .vocabulary,
            key: "term:visible-openai",
            valuePayload: Data("OpenAI".utf8),
            valueFingerprint: "OpenAI",
            identityHash: "visible-openai",
            scope: .app("com.apple.mail"),
            confidence: 0.80,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            lastConfirmedAt: Date(timeIntervalSince1970: 0),
            sourceEventIDs: []
        ))

        try insertCorruptMemoryRow(
            databaseURL: context.databaseURL,
            identityHash: "hidden-corrupt-scene",
            type: .scene,
            status: .hidden,
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let rows = try await context.store.listMemories(
            matching: MemoryCenterQuery(
                statuses: [.active],
                types: [.vocabulary],
                limit: 1
            )
        )

        #expect(rows.count == 1)
        #expect(rows[0].identityHash == "visible-openai")
    }

    private func makeTestStore(now: Date = Date(timeIntervalSince1970: 0)) throws -> MemoryStorageSQLiteStore {
        try makeTestStoreContext(now: now).store
    }

    private func makeTestStoreContext(
        now: Date = Date(timeIntervalSince1970: 0)
    ) throws -> (store: MemoryStorageSQLiteStore, databaseURL: URL) {
        let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try MemoryStorageSQLiteStore(
            databaseURL: databaseURL,
            keyProvider: StaticMemoryKeyProvider(),
            now: { now }
        )
        return (store, databaseURL)
    }

    private func insertCorruptMemoryRow(
        databaseURL: URL,
        identityHash: String,
        type: MemoryType,
        status: MemoryStatus,
        updatedAt: Date
    ) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK, let handle else {
            throw CorruptMemoryInsertError.openFailed
        }
        defer { sqlite3_close(handle) }

        let sql = """
        INSERT INTO memories (
            identity_hash, id, type, memory_key, value_payload, value_fingerprint,
            scope_kind, scope_app_identifier, scope_window_title, scope_field_role,
            scope_field_label, confidence, status, created_at, updated_at,
            last_confirmed_at, source_event_ids
        ) VALUES (
            '\(identityHash)',
            '\(UUID().uuidString)',
            '\(type.rawValue)',
            'corrupt:\(identityHash)',
            X'00',
            'corrupt',
            'app',
            'com.apple.mail',
            NULL,
            NULL,
            NULL,
            0.10,
            '\(status.rawValue)',
            0,
            \(updatedAt.timeIntervalSince1970),
            NULL,
            X'5B5D'
        );
        """

        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw CorruptMemoryInsertError.insertFailed(String(cString: sqlite3_errmsg(handle)))
        }
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

private enum CorruptMemoryInsertError: Error {
    case openFailed
    case insertFailed(String)
}
