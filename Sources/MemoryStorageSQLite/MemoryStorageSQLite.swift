import Foundation
import MemoryDomain
import SQLite3

public actor MemoryStorageSQLiteStore: MemoryStore {
    private static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
    private static let memorySelectSQL = """
        SELECT identity_hash, id, type, memory_key, value_payload, value_fingerprint,
               scope_kind, scope_app_identifier, scope_window_title, scope_field_role,
               scope_field_label, confidence, status, created_at, updated_at,
               last_confirmed_at, source_event_ids
        FROM memories
        ORDER BY updated_at DESC;
        """

    private let databaseURL: URL
    nonisolated(unsafe) private let db: OpaquePointer
    private let cipher: MemoryCipher
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL,
        keyProvider: any MemoryKeyProviding,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.databaseURL = databaseURL
        self.now = now
        self.cipher = try MemoryCipher(masterKeyData: keyProvider.loadOrCreateMasterKey())

        var handle: OpaquePointer?
        let openStatus = sqlite3_open(databaseURL.path, &handle)
        guard openStatus == SQLITE_OK, let handle else {
            throw SQLiteStoreError.openFailed(status: openStatus, path: databaseURL.path)
        }

        self.db = handle
        try Self.migrate(db: handle)
    }

    deinit {
        sqlite3_close(db)
    }

    public func insert(event: InputEvent) async throws {
        let sql = """
        INSERT OR REPLACE INTO input_events (
            id, timestamp, language_code, locale_identifier, app_identifier, app_name,
            window_title, page_title, field_role, field_label, sensitivity_class,
            observation_status, action_type, raw_transcript, polished_text, inserted_text,
            final_user_edited_text, outcome, duration_ms, source, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try execute(sql) { statement in
            let storedEvent = sanitizedEvent(event)
            bindText(storedEvent.id.uuidString, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, storedEvent.timestamp.timeIntervalSince1970)
            bindText(storedEvent.languageCode, to: statement, at: 3)
            bindText(storedEvent.localeIdentifier, to: statement, at: 4)
            bindText(storedEvent.appIdentifier, to: statement, at: 5)
            bindText(storedEvent.appName, to: statement, at: 6)
            bindOptionalText(storedEvent.windowTitle, to: statement, at: 7)
            bindOptionalText(storedEvent.pageTitle, to: statement, at: 8)
            bindText(storedEvent.fieldRole, to: statement, at: 9)
            bindOptionalText(storedEvent.fieldLabel, to: statement, at: 10)
            bindText(storedEvent.sensitivityClass.rawValue, to: statement, at: 11)
            bindText(storedEvent.observationStatus.rawValue, to: statement, at: 12)
            bindText(storedEvent.actionType.rawValue, to: statement, at: 13)
            try bindOptionalEncryptedText(storedEvent.rawTranscript, to: statement, at: 14)
            try bindOptionalEncryptedText(storedEvent.polishedText, to: statement, at: 15)
            try bindOptionalEncryptedText(storedEvent.insertedText, to: statement, at: 16)
            try bindOptionalEncryptedText(storedEvent.finalUserEditedText, to: statement, at: 17)
            bindText(storedEvent.outcome.rawValue, to: statement, at: 18)
            sqlite3_bind_int64(statement, 19, sqlite3_int64(storedEvent.durationMs))
            bindText(storedEvent.source.rawValue, to: statement, at: 20)
            sqlite3_bind_double(statement, 21, storedEvent.timestamp.timeIntervalSince1970 + Self.retentionInterval)
        }
    }

    public func upsert(memory: MemoryItem) async throws {
        let sql = """
        INSERT OR REPLACE INTO memories (
            identity_hash, id, type, memory_key, value_payload, value_fingerprint,
            scope_kind, scope_app_identifier, scope_window_title, scope_field_role,
            scope_field_label, confidence, status, created_at, updated_at,
            last_confirmed_at, source_event_ids
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        try execute(sql) { statement in
            bindText(memory.identityHash, to: statement, at: 1)
            bindText(memory.id.uuidString, to: statement, at: 2)
            bindText(memory.type.rawValue, to: statement, at: 3)
            bindText(memory.key, to: statement, at: 4)
            let encryptedPayload = try cipher.encrypt(memory.valuePayload)
            try bindBlob(encryptedPayload, to: statement, at: 5)
            bindText(memory.valueFingerprint, to: statement, at: 6)
            let record = ScopeRecord(scope: memory.scope)
            bindText(record.kind, to: statement, at: 7)
            bindOptionalText(record.appIdentifier, to: statement, at: 8)
            bindOptionalText(record.windowTitle, to: statement, at: 9)
            bindOptionalText(record.fieldRole, to: statement, at: 10)
            bindOptionalText(record.fieldLabel, to: statement, at: 11)
            sqlite3_bind_double(statement, 12, memory.confidence)
            bindText(memory.status.rawValue, to: statement, at: 13)
            sqlite3_bind_double(statement, 14, memory.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 15, memory.updatedAt.timeIntervalSince1970)
            if let lastConfirmedAt = memory.lastConfirmedAt {
                sqlite3_bind_double(statement, 16, lastConfirmedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            let eventIDs = try JSONEncoder().encode(memory.sourceEventIDs.map(\.uuidString))
            try bindBlob(eventIDs, to: statement, at: 17)
        }
    }

    public func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        let rows: [MemoryItem] = try self.query(Self.memorySelectSQL, bind: { _ in }) { statement in
            let memory = try decodeMemory(from: statement)
            guard query.statuses.contains(memory.status) else {
                return nil
            }
            guard query.types.contains(memory.type) else {
                return nil
            }
            return memory
        }

        if let limit = query.limit {
            return Array(rows.prefix(limit))
        }
        return rows
    }

    public func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        let memories = try await listMemories(matching: MemoryCenterQuery())
        return memories.filter { memory in
            memory.scope.matches(request: request)
        }
    }

    public func markDeleted(identityHash: String, deletedAt: Date) async throws {
        let sql = """
        UPDATE memories
        SET status = ?, updated_at = ?
        WHERE identity_hash = ?;
        """

        try execute(sql) { statement in
            bindText(MemoryStatus.deleted.rawValue, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, deletedAt.timeIntervalSince1970)
            bindText(identityHash, to: statement, at: 3)
        }
    }

    public func markHidden(identityHash: String, hiddenAt: Date) async throws {
        let sql = """
        UPDATE memories
        SET status = ?, updated_at = ?
        WHERE identity_hash = ?;
        """

        try execute(sql) { statement in
            bindText(MemoryStatus.hidden.rawValue, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, hiddenAt.timeIntervalSince1970)
            bindText(identityHash, to: statement, at: 3)
        }
    }

    func compactExpiredEvents() async throws {
        let sql = "DELETE FROM input_events WHERE expires_at < ?;"
        try execute(sql) { statement in
            sqlite3_bind_double(statement, 1, now().timeIntervalSince1970)
        }
    }

    func debugFetchEvent(id: UUID) async throws -> InputEvent {
        let sql = """
        SELECT id, timestamp, language_code, locale_identifier, app_identifier, app_name,
               window_title, page_title, field_role, field_label, sensitivity_class,
               observation_status, action_type, raw_transcript, polished_text, inserted_text,
               final_user_edited_text, outcome, duration_ms, source
        FROM input_events
        WHERE id = ?
        LIMIT 1;
        """

        let rows = try query(sql) { statement in
            bindText(id.uuidString, to: statement, at: 1)
        } rowDecoder: { statement in
            InputEvent(
                id: try readUUID(from: statement, at: 0),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                languageCode: try readText(from: statement, at: 2),
                localeIdentifier: try readText(from: statement, at: 3),
                appIdentifier: try readText(from: statement, at: 4),
                appName: try readText(from: statement, at: 5),
                windowTitle: readOptionalText(from: statement, at: 6),
                pageTitle: readOptionalText(from: statement, at: 7),
                fieldRole: try readText(from: statement, at: 8),
                fieldLabel: readOptionalText(from: statement, at: 9),
                sensitivityClass: try readEnum(SensitivityClass.self, from: statement, at: 10),
                observationStatus: try readEnum(ObservationStatus.self, from: statement, at: 11),
                actionType: try readEnum(MemoryActionType.self, from: statement, at: 12),
                rawTranscript: try decryptOptionalText(from: statement, at: 13),
                polishedText: try decryptOptionalText(from: statement, at: 14),
                insertedText: try decryptOptionalText(from: statement, at: 15),
                finalUserEditedText: try decryptOptionalText(from: statement, at: 16),
                outcome: try readEnum(InputEventOutcome.self, from: statement, at: 17),
                durationMs: Int(sqlite3_column_int64(statement, 18)),
                source: try readEnum(InputEventSource.self, from: statement, at: 19)
            )
        }

        guard let event = rows.first else {
            throw SQLiteStoreError.missingRow(id.uuidString)
        }
        return event
    }

    func debugEventCount() async throws -> Int {
        let sql = "SELECT COUNT(*) FROM input_events;"
        let rows = try query(sql, bind: { _ in }) { statement in
            Int(sqlite3_column_int64(statement, 0))
        }
        return rows.first ?? 0
    }

    private func decodeMemory(from statement: OpaquePointer) throws -> MemoryItem {
        let scope = try decodeScope(from: statement)
        let eventIDsBlob = try readBlob(from: statement, at: 16)
        let eventIDStrings = try JSONDecoder().decode([String].self, from: eventIDsBlob)
        let sourceEventIDs = try eventIDStrings.map { value in
            guard let uuid = UUID(uuidString: value) else {
                throw SQLiteStoreError.decodeFailed("Invalid UUID \(value)")
            }
            return uuid
        }

        return MemoryItem(
            id: try readUUID(from: statement, at: 1),
            type: try readEnum(MemoryType.self, from: statement, at: 2),
            key: try readText(from: statement, at: 3),
            valuePayload: try cipher.decrypt(readBlob(from: statement, at: 4)),
            valueFingerprint: try readText(from: statement, at: 5),
            identityHash: try readText(from: statement, at: 0),
            scope: scope,
            confidence: sqlite3_column_double(statement, 11),
            status: try readEnum(MemoryStatus.self, from: statement, at: 12),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 13)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 14)),
            lastConfirmedAt: sqlite3_column_type(statement, 15) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 15)),
            sourceEventIDs: sourceEventIDs
        )
    }

    private static func migrate(db: OpaquePointer) throws {
        let statements = [
            "PRAGMA foreign_keys = ON;",
            """
            CREATE TABLE IF NOT EXISTS input_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                language_code TEXT NOT NULL,
                locale_identifier TEXT NOT NULL,
                app_identifier TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT,
                page_title TEXT,
                field_role TEXT NOT NULL,
                field_label TEXT,
                sensitivity_class TEXT NOT NULL,
                observation_status TEXT NOT NULL,
                action_type TEXT NOT NULL,
                raw_transcript BLOB,
                polished_text BLOB,
                inserted_text BLOB,
                final_user_edited_text BLOB,
                outcome TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                source TEXT NOT NULL,
                expires_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS memories (
                identity_hash TEXT PRIMARY KEY,
                id TEXT NOT NULL,
                type TEXT NOT NULL,
                memory_key TEXT NOT NULL,
                value_payload BLOB NOT NULL,
                value_fingerprint TEXT NOT NULL,
                scope_kind TEXT NOT NULL,
                scope_app_identifier TEXT,
                scope_window_title TEXT,
                scope_field_role TEXT,
                scope_field_label TEXT,
                confidence REAL NOT NULL,
                status TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                last_confirmed_at REAL,
                source_event_ids BLOB NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_input_events_expires_at ON input_events (expires_at);",
            "CREATE INDEX IF NOT EXISTS idx_memories_status_updated_at ON memories (status, updated_at DESC);"
        ]

        for sql in statements {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                throw SQLiteStoreError.migrationFailed(message: message)
            }
        }
    }

    private func execute(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.executionFailed(sql: sql, message: lastErrorMessage())
        }
    }

    private func query<T>(
        _ sql: String,
        bind: (OpaquePointer) throws -> Void,
        rowDecoder: (OpaquePointer) throws -> T?
    ) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement)

        var results: [T] = []
        while true {
            let status = sqlite3_step(statement)
            switch status {
            case SQLITE_ROW:
                if let row = try rowDecoder(statement) {
                    results.append(row)
                }
            case SQLITE_DONE:
                return results
            default:
                throw SQLiteStoreError.executionFailed(sql: sql, message: lastErrorMessage())
            }
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw SQLiteStoreError.prepareFailed(sql: sql, message: lastErrorMessage())
        }
        return statement
    }

    private func sanitizedEvent(_ event: InputEvent) -> InputEvent {
        guard event.sensitivityClass == .secureExcluded || event.sensitivityClass == .optOut else {
            return event
        }

        return InputEvent(
            id: event.id,
            timestamp: event.timestamp,
            languageCode: event.languageCode,
            localeIdentifier: event.localeIdentifier,
            appIdentifier: event.appIdentifier,
            appName: event.appName,
            windowTitle: event.windowTitle,
            pageTitle: event.pageTitle,
            fieldRole: event.fieldRole,
            fieldLabel: event.fieldLabel,
            sensitivityClass: event.sensitivityClass,
            observationStatus: event.observationStatus,
            actionType: event.actionType,
            rawTranscript: nil,
            polishedText: nil,
            insertedText: nil,
            finalUserEditedText: nil,
            outcome: event.outcome,
            durationMs: event.durationMs,
            source: event.source
        )
    }

    private func decodeScope(from statement: OpaquePointer) throws -> MemoryScope {
        let kind = try readText(from: statement, at: 6)
        let appIdentifier = readOptionalText(from: statement, at: 7)
        let windowTitle = readOptionalText(from: statement, at: 8)
        let fieldRole = readOptionalText(from: statement, at: 9)
        let fieldLabel = readOptionalText(from: statement, at: 10)

        switch kind {
        case ScopeRecord.Kind.global:
            return .global
        case ScopeRecord.Kind.app:
            guard let appIdentifier else {
                throw SQLiteStoreError.decodeFailed("Missing appIdentifier for app scope")
            }
            return .app(appIdentifier)
        case ScopeRecord.Kind.window:
            guard let appIdentifier, let windowTitle else {
                throw SQLiteStoreError.decodeFailed("Missing window scope values")
            }
            return .window(appIdentifier: appIdentifier, windowTitle: windowTitle)
        case ScopeRecord.Kind.field:
            guard let appIdentifier, let fieldRole else {
                throw SQLiteStoreError.decodeFailed("Missing field scope values")
            }
            return .field(
                appIdentifier: appIdentifier,
                windowTitle: windowTitle,
                fieldRole: fieldRole,
                fieldLabel: fieldLabel
            )
        default:
            throw SQLiteStoreError.decodeFailed("Unknown scope kind \(kind)")
        }
    }

    private func bindText(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, to: statement, at: index)
    }

    private func bindOptionalEncryptedText(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let encrypted = try cipher.encrypt(value)
        try bindBlob(encrypted, to: statement, at: index)
    }

    private func bindBlob(_ value: Data, to statement: OpaquePointer, at index: Int32) throws {
        let status = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
        guard status == SQLITE_OK else {
            throw SQLiteStoreError.bindFailed(message: lastErrorMessage())
        }
    }

    private func decryptOptionalText(from statement: OpaquePointer, at index: Int32) throws -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return try cipher.decryptToString(readBlob(from: statement, at: index))
    }

    private func readText(from statement: OpaquePointer, at index: Int32) throws -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            throw SQLiteStoreError.decodeFailed("Expected text at column \(index)")
        }
        return String(cString: cString)
    }

    private func readOptionalText(from statement: OpaquePointer, at index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func readBlob(from statement: OpaquePointer, at index: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else {
            throw SQLiteStoreError.decodeFailed("Expected blob at column \(index)")
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private func readUUID(from statement: OpaquePointer, at index: Int32) throws -> UUID {
        let value = try readText(from: statement, at: index)
        guard let uuid = UUID(uuidString: value) else {
            throw SQLiteStoreError.decodeFailed("Invalid UUID \(value)")
        }
        return uuid
    }

    private func readEnum<T: RawRepresentable>(
        _ type: T.Type,
        from statement: OpaquePointer,
        at index: Int32
    ) throws -> T where T.RawValue == String {
        let value = try readText(from: statement, at: index)
        guard let enumValue = T(rawValue: value) else {
            throw SQLiteStoreError.decodeFailed("Invalid enum value \(value)")
        }
        return enumValue
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }
}

private struct ScopeRecord {
    enum Kind {
        static let global = "global"
        static let app = "app"
        static let window = "window"
        static let field = "field"
    }

    let kind: String
    let appIdentifier: String?
    let windowTitle: String?
    let fieldRole: String?
    let fieldLabel: String?

    init(scope: MemoryScope) {
        switch scope {
        case .global:
            kind = Kind.global
            appIdentifier = nil
            windowTitle = nil
            fieldRole = nil
            fieldLabel = nil
        case .app(let appIdentifier):
            kind = Kind.app
            self.appIdentifier = appIdentifier
            windowTitle = nil
            fieldRole = nil
            fieldLabel = nil
        case .window(let appIdentifier, let windowTitle):
            kind = Kind.window
            self.appIdentifier = appIdentifier
            self.windowTitle = windowTitle
            fieldRole = nil
            fieldLabel = nil
        case .field(let appIdentifier, let windowTitle, let fieldRole, let fieldLabel):
            kind = Kind.field
            self.appIdentifier = appIdentifier
            self.windowTitle = windowTitle
            self.fieldRole = fieldRole
            self.fieldLabel = fieldLabel
        }
    }
}

private extension MemoryScope {
    func matches(request: RecallRequest) -> Bool {
        switch self {
        case .global:
            return true
        case .app(let appIdentifier):
            return appIdentifier == request.appIdentifier
        case .window(let appIdentifier, let windowTitle):
            return appIdentifier == request.appIdentifier && windowTitle == request.windowTitle
        case .field(let appIdentifier, let windowTitle, let fieldRole, let fieldLabel):
            guard appIdentifier == request.appIdentifier else { return false }
            guard fieldRole == request.fieldRole else { return false }
            if let windowTitle, windowTitle != request.windowTitle {
                return false
            }
            if let fieldLabel, fieldLabel != request.fieldLabel {
                return false
            }
            return true
        }
    }
}

private enum SQLiteStoreError: LocalizedError {
    case openFailed(status: Int32, path: String)
    case prepareFailed(sql: String, message: String)
    case executionFailed(sql: String, message: String)
    case bindFailed(message: String)
    case migrationFailed(message: String)
    case decodeFailed(String)
    case missingRow(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let status, let path):
            return "Failed to open SQLite database at \(path) (\(status))."
        case .prepareFailed(_, let message):
            return "Failed to prepare SQLite statement: \(message)"
        case .executionFailed(_, let message):
            return "Failed to execute SQLite statement: \(message)"
        case .bindFailed(let message):
            return "Failed to bind SQLite value: \(message)"
        case .migrationFailed(let message):
            return "Failed to migrate SQLite schema: \(message)"
        case .decodeFailed(let message):
            return "Failed to decode SQLite row: \(message)"
        case .missingRow(let identifier):
            return "No stored row matched \(identifier)."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
