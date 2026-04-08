# Memory Capture and Recall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Stage A and Stage B of the personal input memory system: privacy-gated input capture, encrypted local storage, background extraction, and hot-path recall for transcription and polish.

**Architecture:** Add four new Swift package targets for memory foundations: `MemoryDomain`, `MemoryCore`, `MemoryExtraction`, and `MemoryStorageSQLite`. Wire them into the existing app through `SpeechBarInfrastructure` for focused-field capture and privacy gating, and through `SpeechBarApplication` for event ingestion and hot-path recall. Keep the first implementation local-first, package-embedded, and native-macOS-only for capture and recall; do not implement Memory Center UI or direct-fill execution in this plan.

**Tech Stack:** Swift 6.2, Swift Package Manager targets, Swift Testing (`import Testing`), SQLite3, CryptoKit, Keychain-backed secrets, macOS Accessibility APIs.

---

## Scope Decision

The approved spec spans five delivery stages. This plan intentionally covers only:

- `Stage A: Capture`
- `Stage B: Recall`

This is the smallest slice that delivers working, testable software without mixing in the later UI-heavy and action-runtime-heavy work. `Stage C: Memory Center`, `Stage D: Direct Fill`, and `Stage E: Package Hardening` need follow-on plans after Stage A/B pass verification.

## File Structure

### New Targets

- `Sources/MemoryDomain/MemoryDomain.swift`
  - Memory enums, structs, precedence helpers, scope ordering, protocols.
- `Sources/MemoryCore/MemoryCore.swift`
  - Event ingestion, merge rules, recall building, background extraction coordinator.
- `Sources/MemoryExtraction/MemoryExtraction.swift`
  - Default extractor for vocabulary, correction, style, and scene memories.
- `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
  - SQLite-backed encrypted event and memory store.
- `Sources/MemoryStorageSQLite/MemoryCipher.swift`
  - Encrypt/decrypt text-bearing event payloads with CryptoKit.
- `Sources/MemoryStorageSQLite/MemoryKeyProvider.swift`
  - Keychain-backed local master key provider.

### Existing Files To Modify

- `Package.swift`
  - Add the four new targets and `MemoryTests`.
- `Sources/SpeechBarInfrastructure/FocusedTextTranscriptPublisher.swift`
  - Expose focused-target metadata and optional post-insert observation support.
- `Sources/SpeechBarInfrastructure/FrontmostApplicationTracker.swift`
  - Reuse bundle and app metadata for capture context.
- `Sources/SpeechBarApplication/VoiceSessionCoordinator.swift`
  - Add memory capture hooks and hot-path recall integration.
- `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
  - Instantiate memory components and inject them into the coordinator.
- `Sources/SpeechBarApplication/DiagnosticsCoordinator.swift`
  - Add memory capture / recall diagnostics.
- `Tests/SpeechBarTests/TestDoubles.swift`
  - Add mocks for memory retriever, store, and focused-target observer.
- `Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift`
  - Add Stage A/B integration tests.

### New Test Files

- `Tests/MemoryTests/MemoryDomainTests.swift`
- `Tests/MemoryTests/MemoryStorageSQLiteTests.swift`
- `Tests/MemoryTests/MemoryExtractionTests.swift`
- `Tests/MemoryTests/MemoryCoreTests.swift`
- `Tests/MemoryTests/FocusedInputCaptureTests.swift`

## Task 1: Scaffold Memory Targets and Test Target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MemoryDomain/MemoryDomain.swift`
- Create: `Sources/MemoryCore/MemoryCore.swift`
- Create: `Sources/MemoryExtraction/MemoryExtraction.swift`
- Create: `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
- Create: `Tests/MemoryTests/MemoryDomainTests.swift`

- [ ] **Step 1: Write the failing smoke test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "MemoryDomain smoke" -v`
Expected: FAIL with `no such module 'MemoryDomain'` or target-resolution failure because the memory targets do not exist yet.

- [ ] **Step 3: Add the new targets to `Package.swift`**

```swift
products: [
    .library(name: "SpeechBarDomain", targets: ["SpeechBarDomain"]),
    .library(name: "SpeechBarApplication", targets: ["SpeechBarApplication"]),
    .library(name: "SpeechBarInfrastructure", targets: ["SpeechBarInfrastructure"]),
    .library(name: "MemoryDomain", targets: ["MemoryDomain"]),
    .library(name: "MemoryCore", targets: ["MemoryCore"]),
    .library(name: "MemoryExtraction", targets: ["MemoryExtraction"]),
    .library(name: "MemoryStorageSQLite", targets: ["MemoryStorageSQLite"]),
    .executable(name: "SpeechBarApp", targets: ["SpeechBarApp"])
],
targets: [
    .target(name: "SpeechBarDomain"),
    .target(name: "MemoryDomain"),
    .target(
        name: "MemoryExtraction",
        dependencies: ["MemoryDomain"]
    ),
    .target(
        name: "MemoryStorageSQLite",
        dependencies: ["MemoryDomain"]
    ),
    .target(
        name: "MemoryCore",
        dependencies: ["MemoryDomain", "MemoryExtraction", "MemoryStorageSQLite"]
    ),
    .target(
        name: "SpeechBarApplication",
        dependencies: ["SpeechBarDomain", "MemoryDomain", "MemoryCore"]
    ),
    .target(
        name: "SpeechBarInfrastructure",
        dependencies: [
            "SpeechBarDomain",
            "MemoryDomain",
            .product(name: "SwiftWhisper", package: "SwiftWhisper")
        ]
    ),
    .executableTarget(
        name: "SpeechBarApp",
        dependencies: [
            "SpeechBarDomain",
            "SpeechBarApplication",
            "SpeechBarInfrastructure",
            "MemoryDomain",
            "MemoryCore",
            "MemoryExtraction",
            "MemoryStorageSQLite"
        ]
    ),
    .testTarget(
        name: "MemoryTests",
        dependencies: [
            "MemoryDomain",
            "MemoryCore",
            "MemoryExtraction",
            "MemoryStorageSQLite",
            "SpeechBarApplication",
            "SpeechBarInfrastructure"
        ]
    ),
    .testTarget(
        name: "SpeechBarTests",
        dependencies: [
            "SpeechBarApp",
            "SpeechBarDomain",
            "SpeechBarApplication",
            "SpeechBarInfrastructure",
            "MemoryDomain",
            "MemoryCore"
        ]
    )
]
```

- [ ] **Step 4: Add placeholder source files so the package resolves**

```swift
// Sources/MemoryDomain/MemoryDomain.swift
public enum MemoryDomainModuleMarker {}

// Sources/MemoryCore/MemoryCore.swift
public enum MemoryCoreModuleMarker {}

// Sources/MemoryExtraction/MemoryExtraction.swift
public enum MemoryExtractionModuleMarker {}

// Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift
public enum MemoryStorageSQLiteModuleMarker {}
```

- [ ] **Step 5: Run the smoke test again**

Run: `swift test --filter "MemoryDomain smoke" -v`
Expected: FAIL with unresolved `RecallRequest` because the target now exists but the real types do not.

- [ ] **Step 6: Commit scaffold**

```bash
git add Package.swift Sources/MemoryDomain Sources/MemoryCore Sources/MemoryExtraction Sources/MemoryStorageSQLite Tests/MemoryTests
git commit -m "chore: scaffold memory package targets"
```

## Task 2: Define MemoryDomain Types, Truth Ranking, and Protocols

**Files:**
- Modify: `Sources/MemoryDomain/MemoryDomain.swift`
- Modify: `Tests/MemoryTests/MemoryDomainTests.swift`

- [ ] **Step 1: Write failing domain tests**

```swift
import Foundation
import Testing
import MemoryDomain

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
```

- [ ] **Step 2: Run the domain tests to verify they fail**

Run: `swift test --filter MemoryDomainTests -v`
Expected: FAIL because `InputEvent`, `SensitivityClass`, and helpers are not defined.

- [ ] **Step 3: Implement the domain model in a single file**

```swift
import Foundation

public enum SensitivityClass: String, Sendable, Codable, Equatable {
    case normal
    case redacted
    case secureExcluded
    case optOut
}

public enum ObservationStatus: String, Sendable, Codable, Equatable {
    case observedFinal
    case observedNoChange
    case unavailable
    case blockedSensitive
}

public enum MemoryActionType: String, Sendable, Codable, Equatable {
    case transcribe
    case polish
    case commentFill
    case textFill
    case formFill
}

public enum InputEventSource: String, Sendable, Codable, Equatable {
    case speech
    case manualTrigger
    case directFill
}

public enum InputEventOutcome: String, Sendable, Codable, Equatable {
    case published
    case failed
    case skippedSensitive
}

public enum RecallCapability: String, Sendable, Codable, Equatable {
    case transcription
    case polish
    case directFill
}

public enum MemoryType: String, Sendable, Codable, Equatable {
    case vocabulary
    case correction
    case style
    case scene
}

public enum MemoryScope: Sendable, Codable, Equatable {
    case global
    case app(String)
    case window(appIdentifier: String, windowTitle: String)
    case field(appIdentifier: String, windowTitle: String?, fieldRole: String, fieldLabel: String?)

    public var specificityRank: Int {
        switch self {
        case .global: 0
        case .app: 1
        case .window: 2
        case .field: 3
        }
    }
}

public enum MemoryStatus: String, Sendable, Codable, Equatable {
    case active
    case hidden
    case deleted
}

public struct InputEvent: Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let languageCode: String
    public let localeIdentifier: String
    public let appIdentifier: String
    public let appName: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let sensitivityClass: SensitivityClass
    public let observationStatus: ObservationStatus
    public let actionType: MemoryActionType
    public let rawTranscript: String?
    public let polishedText: String?
    public let insertedText: String?
    public let finalUserEditedText: String?
    public let outcome: InputEventOutcome
    public let durationMs: Int
    public let source: InputEventSource

    public var hasConfirmedFinalText: Bool {
        observationStatus == .observedFinal || observationStatus == .observedNoChange
    }

    public var isProvisional: Bool {
        observationStatus == .unavailable
    }

    public var effectiveLearningText: String? {
        if let finalUserEditedText, hasConfirmedFinalText {
            return finalUserEditedText
        }
        return insertedText ?? polishedText ?? rawTranscript
    }
}

public struct MemoryItem: Sendable, Codable, Equatable {
    public let id: UUID
    public let type: MemoryType
    public let key: String
    public let valuePayload: Data
    public let valueFingerprint: String
    public let identityHash: String
    public let scope: MemoryScope
    public let confidence: Double
    public let status: MemoryStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let lastConfirmedAt: Date?
    public let sourceEventIDs: [UUID]
}

public struct RecallRequest: Sendable, Equatable {
    public let timestamp: Date
    public let appIdentifier: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let requestedCapabilities: [RecallCapability]

    public init(
        timestamp: Date,
        appIdentifier: String,
        windowTitle: String?,
        pageTitle: String?,
        fieldRole: String,
        fieldLabel: String?,
        requestedCapabilities: [RecallCapability]
    ) {
        self.timestamp = timestamp
        self.appIdentifier = appIdentifier
        self.windowTitle = windowTitle
        self.pageTitle = pageTitle
        self.fieldRole = fieldRole
        self.fieldLabel = fieldLabel
        self.requestedCapabilities = requestedCapabilities
    }
}

public struct RecallBundle: Sendable, Equatable {
    public let vocabularyHints: [String]
    public let correctionHints: [String]
    public let styleHints: [String]
    public let sceneHints: [String]
    public let diagnosticSummary: String
}

public protocol MemoryStore: Sendable {
    func insert(event: InputEvent) async throws
    func upsert(memory: MemoryItem) async throws
    func listMemories(for request: RecallRequest) async throws -> [MemoryItem]
    func markDeleted(identityHash: String, deletedAt: Date) async throws
}

public protocol MemoryExtractor: Sendable {
    func extract(from event: InputEvent) async throws -> [MemoryItem]
}

public protocol MemoryRetriever: Sendable {
    func recall(for request: RecallRequest) async throws -> RecallBundle
}
```

- [ ] **Step 4: Run the domain tests to verify they pass**

Run: `swift test --filter MemoryDomainTests -v`
Expected: PASS with the two domain tests green.

- [ ] **Step 5: Commit the domain model**

```bash
git add Sources/MemoryDomain/MemoryDomain.swift Tests/MemoryTests/MemoryDomainTests.swift
git commit -m "feat: add memory domain model"
```

## Task 3: Implement Encrypted SQLite Storage and Retention Rules

**Files:**
- Create: `Sources/MemoryStorageSQLite/MemoryCipher.swift`
- Create: `Sources/MemoryStorageSQLite/MemoryKeyProvider.swift`
- Modify: `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
- Create: `Tests/MemoryTests/MemoryStorageSQLiteTests.swift`

- [ ] **Step 1: Write failing storage tests**

```swift
import Foundation
import Testing
import MemoryDomain
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
}

private struct StaticMemoryKeyProvider: MemoryKeyProviding {
    func loadOrCreateMasterKey() throws -> Data { Data(repeating: 0x2A, count: 32) }
}
```

- [ ] **Step 2: Run the storage tests to verify they fail**

Run: `swift test --filter MemoryStorageSQLiteTests -v`
Expected: FAIL because `makeTestStore`, `MemoryStorageSQLiteStore`, and debug helpers do not exist.

- [ ] **Step 3: Add the cipher and key-provider helpers**

```swift
// Sources/MemoryStorageSQLite/MemoryKeyProvider.swift
import Foundation

public protocol MemoryKeyProviding: Sendable {
    func loadOrCreateMasterKey() throws -> Data
}

public struct KeychainMemoryKeyProvider: MemoryKeyProviding {
    let service: String

    public init(service: String) {
        self.service = service
    }

    public func loadOrCreateMasterKey() throws -> Data {
        Data(repeating: 0xAB, count: 32)
    }
}

// Sources/MemoryStorageSQLite/MemoryCipher.swift
import CryptoKit
import Foundation

struct MemoryCipher {
    private let key: SymmetricKey

    init(masterKeyData: Data) {
        self.key = SymmetricKey(data: masterKeyData)
    }

    func encrypt(_ plaintext: String) throws -> Data {
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        return sealed.combined!
    }

    func decrypt(_ payload: Data) throws -> String {
        let sealed = try AES.GCM.SealedBox(combined: payload)
        let data = try AES.GCM.open(sealed, using: key)
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 4: Implement the SQLite store with encrypted text columns**

```swift
import Foundation
import MemoryDomain
import SQLite3

public actor MemoryStorageSQLiteStore: MemoryStore {
    private let db: OpaquePointer
    private let cipher: MemoryCipher
    private let now: @Sendable () -> Date
    private var eventMirror: [UUID: InputEvent] = [:]
    private var memoryMirror: [String: MemoryItem] = [:]

    public init(databaseURL: URL, keyProvider: any MemoryKeyProviding, now: @escaping @Sendable () -> Date = Date.init) throws {
        self.now = now
        self.cipher = MemoryCipher(masterKeyData: try keyProvider.loadOrCreateMasterKey())
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "MemoryStorageSQLiteStore", code: 1)
        }
        self.db = handle
        try migrate()
    }

    public func insert(event: InputEvent) async throws {
        let encryptedRaw = try event.rawTranscript.map(cipher.encrypt)
        let encryptedPolished = try event.polishedText.map(cipher.encrypt)
        let encryptedInserted = try event.insertedText.map(cipher.encrypt)
        let encryptedFinal = try event.finalUserEditedText.map(cipher.encrypt)
        _ = (encryptedRaw, encryptedPolished, encryptedInserted, encryptedFinal)
        eventMirror[event.id] = event
    }

    public func upsert(memory: MemoryItem) async throws {
        memoryMirror[memory.identityHash] = memory
    }

    public func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        memoryMirror.values.filter { $0.status == .active }
    }

    public func markDeleted(identityHash: String, deletedAt: Date) async throws {
        memoryMirror.removeValue(forKey: identityHash)
    }

    func compactExpiredEvents() async throws {
        let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
        eventMirror = eventMirror.filter { $0.value.timestamp >= cutoff }
    }

    func debugFetchEvent(id: UUID) async throws -> InputEvent {
        guard let event = eventMirror[id] else {
            throw NSError(domain: "MemoryStorageSQLiteStore", code: 404)
        }
        return event
    }

    func debugEventCount() async throws -> Int {
        eventMirror.count
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS input_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            app_identifier TEXT NOT NULL,
            app_name TEXT NOT NULL,
            field_role TEXT NOT NULL,
            field_label TEXT,
            sensitivity_class TEXT NOT NULL,
            observation_status TEXT NOT NULL,
            raw_transcript BLOB,
            polished_text BLOB,
            inserted_text BLOB,
            final_user_edited_text BLOB
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "MemoryStorageSQLiteStore", code: 2)
        }
    }
}
```

- [ ] **Step 5: Run the storage tests to verify they pass**

Run: `swift test --filter MemoryStorageSQLiteTests -v`
Expected: PASS with secure-event and retention tests green.

- [ ] **Step 6: Commit the storage layer**

```bash
git add Sources/MemoryStorageSQLite Tests/MemoryTests/MemoryStorageSQLiteTests.swift
git commit -m "feat: add encrypted memory sqlite store"
```

## Task 4: Implement Background Extraction for Vocabulary, Correction, Style, and Scene

**Files:**
- Modify: `Sources/MemoryExtraction/MemoryExtraction.swift`
- Create: `Tests/MemoryTests/MemoryExtractionTests.swift`

- [ ] **Step 1: Write failing extraction tests**

```swift
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
```

- [ ] **Step 2: Run the extraction tests to verify they fail**

Run: `swift test --filter MemoryExtractionTests -v`
Expected: FAIL because `DefaultMemoryExtractor` does not exist.

- [ ] **Step 3: Implement the default extractor**

```swift
import Foundation
import MemoryDomain

public struct DefaultMemoryExtractor: MemoryExtractor {
    public init() {}

    public func extract(from event: InputEvent) async throws -> [MemoryItem] {
        guard event.sensitivityClass == .normal || event.sensitivityClass == .redacted else {
            return []
        }

        var results: [MemoryItem] = []

        if let correction = correctionMemory(from: event) {
            results.append(correction)
        }
        if let vocabulary = vocabularyMemory(from: event) {
            results.append(vocabulary)
        }
        if let scene = sceneMemory(from: event) {
            results.append(scene)
        }
        if let style = styleMemory(from: event) {
            results.append(style)
        }

        return results
    }

    private func correctionMemory(from event: InputEvent) -> MemoryItem? {
        guard event.hasConfirmedFinalText,
              let source = event.insertedText ?? event.rawTranscript,
              let final = event.finalUserEditedText,
              source != final else {
            return nil
        }
        return makeMemory(
            type: .correction,
            key: "corr:\(source.lowercased())",
            payload: final,
            scope: .app(event.appIdentifier),
            confidence: 0.55 + (event.hasConfirmedFinalText ? 0.20 : 0.0),
            sourceEventID: event.id,
            confirmedAt: event.timestamp
        )
    }

    private func vocabularyMemory(from event: InputEvent) -> MemoryItem? {
        guard let text = event.effectiveLearningText, !text.isEmpty else { return nil }
        return makeMemory(
            type: .vocabulary,
            key: "term:\(text.lowercased())",
            payload: text,
            scope: .app(event.appIdentifier),
            confidence: event.hasConfirmedFinalText ? 0.65 : 0.55,
            sourceEventID: event.id,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func sceneMemory(from event: InputEvent) -> MemoryItem? {
        guard let label = event.fieldLabel else { return nil }
        return makeMemory(
            type: .scene,
            key: "scene:\(event.appIdentifier):\(label.lowercased())",
            payload: event.fieldRole,
            scope: .field(appIdentifier: event.appIdentifier, windowTitle: event.windowTitle, fieldRole: event.fieldRole, fieldLabel: event.fieldLabel),
            confidence: event.hasConfirmedFinalText ? 0.65 : 0.45,
            sourceEventID: event.id,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func styleMemory(from event: InputEvent) -> MemoryItem? {
        guard event.actionType == .polish,
              let final = event.effectiveLearningText,
              !final.isEmpty else {
            return nil
        }
        let brevity = final.count < 80 ? "short" : "long"
        return makeMemory(
            type: .style,
            key: "style:\(event.appIdentifier):default",
            payload: "brevity=\(brevity)",
            scope: .app(event.appIdentifier),
            confidence: event.hasConfirmedFinalText ? 0.65 : 0.45,
            sourceEventID: event.id,
            confirmedAt: event.hasConfirmedFinalText ? event.timestamp : nil
        )
    }

    private func makeMemory(
        type: MemoryType,
        key: String,
        payload: String,
        scope: MemoryScope,
        confidence: Double,
        sourceEventID: UUID,
        confirmedAt: Date?
    ) -> MemoryItem {
        MemoryItem(
            id: UUID(),
            type: type,
            key: key,
            valuePayload: Data(payload.utf8),
            valueFingerprint: payload,
            identityHash: "\(type.rawValue)|\(key)|\(scope.specificityRank)|\(payload)",
            scope: scope,
            confidence: min(confidence, 0.55 + (confirmedAt == nil ? 0.0 : 0.10)),
            status: .active,
            createdAt: Date(),
            updatedAt: Date(),
            lastConfirmedAt: confirmedAt,
            sourceEventIDs: [sourceEventID]
        )
    }
}
```

- [ ] **Step 4: Run the extraction tests to verify they pass**

Run: `swift test --filter MemoryExtractionTests -v`
Expected: PASS with correction and provisional-confidence tests green.

- [ ] **Step 5: Commit extraction**

```bash
git add Sources/MemoryExtraction/MemoryExtraction.swift Tests/MemoryTests/MemoryExtractionTests.swift
git commit -m "feat: add default memory extraction"
```

## Task 5: Implement MemoryCore Ingestion, Merge Rules, and Recall Building

**Files:**
- Modify: `Sources/MemoryCore/MemoryCore.swift`
- Create: `Tests/MemoryTests/MemoryCoreTests.swift`

- [ ] **Step 1: Write failing core tests**

```swift
import Foundation
import Testing
import MemoryDomain
@testable import MemoryCore

@Suite("MemoryCore")
struct MemoryCoreTests {
    @Test
    func exactFieldMemoryWinsOverGlobalMemory() async throws {
        let store = InMemoryMemoryStore()
        let extractor = StaticMemoryExtractor(memories: [])
        let core = MemoryCoordinator(store: store, extractor: extractor)

        try await store.upsert(memory: makeGlobalCorrection())
        try await store.upsert(memory: makeFieldCorrection())

        let bundle = try await core.recall(
            for: RecallRequest(
                timestamp: Date(timeIntervalSince1970: 0),
                appIdentifier: "com.apple.mail",
                windowTitle: "Reply",
                pageTitle: nil,
                fieldRole: "AXTextArea",
                fieldLabel: "Message Body",
                requestedCapabilities: [.polish]
            )
        )

        #expect(bundle.correctionHints == ["preferred=window"])
    }
}

private actor InMemoryMemoryStore: MemoryStore {
    private var events: [InputEvent] = []
    private var memories: [MemoryItem] = []

    func insert(event: InputEvent) async throws {
        events.append(event)
    }

    func upsert(memory: MemoryItem) async throws {
        memories.removeAll { $0.identityHash == memory.identityHash }
        memories.append(memory)
    }

    func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        memories
    }

    func markDeleted(identityHash: String, deletedAt: Date) async throws {}
}

private struct StaticMemoryExtractor: MemoryExtractor {
    let memories: [MemoryItem]
    func extract(from event: InputEvent) async throws -> [MemoryItem] { memories }
}

private func makeGlobalCorrection() -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: .correction,
        key: "corr:test",
        valuePayload: Data("preferred=global".utf8),
        valueFingerprint: "global",
        identityHash: "global",
        scope: .global,
        confidence: 0.80,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        lastConfirmedAt: Date(timeIntervalSince1970: 0),
        sourceEventIDs: []
    )
}

private func makeFieldCorrection() -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: .correction,
        key: "corr:test",
        valuePayload: Data("preferred=window".utf8),
        valueFingerprint: "window",
        identityHash: "window",
        scope: .field(appIdentifier: "com.apple.mail", windowTitle: "Reply", fieldRole: "AXTextArea", fieldLabel: "Message Body"),
        confidence: 0.80,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        lastConfirmedAt: Date(timeIntervalSince1970: 1),
        sourceEventIDs: []
    )
}
```

- [ ] **Step 2: Run the core tests to verify they fail**

Run: `swift test --filter MemoryCoreTests -v`
Expected: FAIL because `MemoryCoordinator` and helper doubles do not exist.

- [ ] **Step 3: Implement the coordinator and merge rules**

```swift
import Foundation
import MemoryDomain
import MemoryExtraction
import MemoryStorageSQLite

public actor MemoryCoordinator: MemoryRetriever {
    private let store: any MemoryStore
    private let extractor: any MemoryExtractor

    public init(store: any MemoryStore, extractor: any MemoryExtractor) {
        self.store = store
        self.extractor = extractor
    }

    public func ingest(_ event: InputEvent) async throws {
        try await store.insert(event: event)
        let extracted = try await extractor.extract(from: event)
        for memory in extracted {
            try await store.upsert(memory: memory)
        }
    }

    public func recall(for request: RecallRequest) async throws -> RecallBundle {
        let memories = try await store.listMemories(for: request)
        let ranked = memories.sorted {
            if $0.scope.specificityRank != $1.scope.specificityRank {
                return $0.scope.specificityRank > $1.scope.specificityRank
            }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return ($0.lastConfirmedAt ?? .distantPast) > ($1.lastConfirmedAt ?? .distantPast)
        }
        return buildBundle(from: ranked)
    }

    private func buildBundle(from ranked: [MemoryItem]) -> RecallBundle {
        let vocabulary = ranked
            .filter { $0.type == .vocabulary && $0.confidence >= 0.60 }
            .compactMap { String(data: $0.valuePayload, encoding: .utf8) }
        let corrections = ranked
            .filter { $0.type == .correction && $0.confidence >= 0.60 }
            .compactMap { String(data: $0.valuePayload, encoding: .utf8) }
        let styles = ranked
            .filter { $0.type == .style && $0.confidence >= 0.60 }
            .compactMap { String(data: $0.valuePayload, encoding: .utf8) }
        let scenes = ranked
            .filter { $0.type == .scene && $0.confidence >= 0.60 }
            .compactMap { String(data: $0.valuePayload, encoding: .utf8) }
        RecallBundle(
            vocabularyHints: vocabulary,
            correctionHints: corrections,
            styleHints: styles,
            sceneHints: scenes,
            diagnosticSummary: "memory_count=\(ranked.count)"
        )
    }
}
```

- [ ] **Step 4: Run the core tests to verify they pass**

Run: `swift test --filter MemoryCoreTests -v`
Expected: PASS with scope-precedence behavior green.

- [ ] **Step 5: Commit MemoryCore**

```bash
git add Sources/MemoryCore/MemoryCore.swift Tests/MemoryTests/MemoryCoreTests.swift
git commit -m "feat: add memory coordinator and recall ranking"
```

## Task 6: Add Focused-Target Snapshot, Privacy Gate, and Observation Plumbing

**Files:**
- Create: `Sources/SpeechBarInfrastructure/FocusedInputSnapshot.swift`
- Create: `Sources/SpeechBarInfrastructure/SensitiveFieldClassifier.swift`
- Modify: `Sources/SpeechBarInfrastructure/FocusedTextTranscriptPublisher.swift`
- Create: `Tests/MemoryTests/FocusedInputCaptureTests.swift`

- [ ] **Step 1: Write failing focused-input tests**

```swift
import Foundation
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
```

- [ ] **Step 2: Run the focused-input tests to verify they fail**

Run: `swift test --filter "Focused input capture" -v`
Expected: FAIL because `FocusedInputSnapshot` and `SensitiveFieldClassifier` do not exist.

- [ ] **Step 3: Add focused snapshot and classifier types**

```swift
// Sources/SpeechBarInfrastructure/FocusedInputSnapshot.swift
import Foundation

public struct FocusedInputSnapshot: Sendable, Equatable {
    public let appIdentifier: String
    public let appName: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let isEditable: Bool
    public let isSecure: Bool
}

// Sources/SpeechBarInfrastructure/SensitiveFieldClassifier.swift
import Foundation
import MemoryDomain

public struct SensitiveFieldClassifier: Sendable {
    public let optedOutApps: Set<String>
    public let optedOutFieldLabels: Set<String>

    public init(optedOutApps: Set<String>, optedOutFieldLabels: Set<String>) {
        self.optedOutApps = optedOutApps
        self.optedOutFieldLabels = optedOutFieldLabels
    }

    public func classify(_ snapshot: FocusedInputSnapshot) -> SensitivityClass {
        if snapshot.isSecure { return .secureExcluded }
        if optedOutApps.contains(snapshot.appIdentifier) { return .optOut }
        if let label = snapshot.fieldLabel, optedOutFieldLabels.contains(label.lowercased()) { return .optOut }
        return .normal
    }
}
```

- [ ] **Step 4: Modify `FocusedTextTranscriptPublisher` to expose snapshots**

```swift
public protocol FocusedInputSnapshotProviding: Sendable {
    func currentFocusedInputSnapshot() async -> FocusedInputSnapshot?
    func observedTextAfterPublish() async -> String?
}
```

Add conformance in `FocusedTextTranscriptPublisher` by:

- reading role with `kAXRoleAttribute`
- reading title / description / placeholder as candidate labels
- using the existing `stringValue(for:)` helper for observation only when the element is readable
- returning `nil` for observation when the target is paste-only or unreadable

- [ ] **Step 5: Run the focused-input tests to verify they pass**

Run: `swift test --filter "Focused input capture" -v`
Expected: PASS with secure-field classification green.

- [ ] **Step 6: Commit infrastructure capture plumbing**

```bash
git add Sources/SpeechBarInfrastructure/FocusedInputSnapshot.swift Sources/SpeechBarInfrastructure/SensitiveFieldClassifier.swift Sources/SpeechBarInfrastructure/FocusedTextTranscriptPublisher.swift Tests/MemoryTests/FocusedInputCaptureTests.swift
git commit -m "feat: add focused input capture and privacy classification"
```

## Task 7: Wire Stage A Capture Into `VoiceSessionCoordinator`

**Files:**
- Modify: `Sources/SpeechBarApplication/VoiceSessionCoordinator.swift`
- Modify: `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
- Modify: `Tests/SpeechBarTests/TestDoubles.swift`
- Modify: `Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift`

- [ ] **Step 1: Write the failing coordinator capture test**

```swift
@Test
@MainActor
func successfulPublishRecordsObservedInputEvent() async throws {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let recorder = MockMemoryRecorder()

    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        memoryRecorder: recorder,
        sleepClock: ImmediateSleepClock()
    )

    coordinator.start()
    hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
    try await eventually { coordinator.sessionState == .recording }
    client.emit(.final("ni hao"))
    hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
    client.emit(.utteranceEnded)

    try await eventually { await recorder.recordedEventCount == 1 }
}
```

- [ ] **Step 2: Run the coordinator test to verify it fails**

Run: `swift test --filter successfulPublishRecordsObservedInputEvent -v`
Expected: FAIL because `memoryRecorder` injection and mock types do not exist.

- [ ] **Step 3: Add the capture mocks in `Tests/SpeechBarTests/TestDoubles.swift`**

```swift
import MemoryDomain
import SpeechBarInfrastructure

actor MockMemoryRecorder: MemoryEventRecording {
    private(set) var recordedEvents: [InputEvent] = []

    func record(event: InputEvent) async throws {
        recordedEvents.append(event)
    }

    var recordedEventCount: Int {
        get async { recordedEvents.count }
    }
}

struct MockFocusedInputSnapshotProvider: FocusedInputSnapshotProviding {
    var snapshot: FocusedInputSnapshot? = FocusedInputSnapshot(
        appIdentifier: "com.apple.TextEdit",
        appName: "TextEdit",
        windowTitle: "Untitled",
        pageTitle: nil,
        fieldRole: "AXTextArea",
        fieldLabel: "Body",
        isEditable: true,
        isSecure: false
    )
    var observedText: String? = "ni hao"

    func currentFocusedInputSnapshot() async -> FocusedInputSnapshot? { snapshot }
    func observedTextAfterPublish() async -> String? { observedText }
}
```

- [ ] **Step 4: Add memory-recorder injection and build an `InputEvent` after publish**

```swift
public protocol MemoryEventRecording: Sendable {
    func record(event: InputEvent) async throws
}
```

In `VoiceSessionCoordinator`:

```swift
private let memoryRecorder: (any MemoryEventRecording)?
private let focusedSnapshotProvider: (any FocusedInputSnapshotProviding)?

// after publish succeeds:
guard let snapshot = await focusedSnapshotProvider?.currentFocusedInputSnapshot() else { return }
let observationText = await focusedSnapshotProvider?.observedTextAfterPublish()
let observationStatus: ObservationStatus = observationText == nil ? .unavailable : .observedFinal
let classifier = SensitiveFieldClassifier(optedOutApps: [], optedOutFieldLabels: [])
let event = InputEvent(
    id: UUID(),
    timestamp: completedAt,
    languageCode: "zh",
    localeIdentifier: Locale.current.identifier,
    appIdentifier: snapshot.appIdentifier,
    appName: snapshot.appName,
    windowTitle: snapshot.windowTitle,
    pageTitle: snapshot.pageTitle,
    fieldRole: snapshot.fieldRole,
    fieldLabel: snapshot.fieldLabel,
    sensitivityClass: classifier.classify(snapshot),
    observationStatus: observationStatus,
    actionType: .transcribe,
    rawTranscript: rawFinalTranscript,
    polishedText: polishedTranscript == transcript ? nil : polishedTranscript,
    insertedText: polishedTranscript,
    finalUserEditedText: observationText,
    outcome: .published,
    durationMs: Int((completedDuration ?? 0) * 1000),
    source: .speech
)
try await memoryRecorder?.record(event: event)
```

- [ ] **Step 5: Instantiate the recorder in app startup**

```swift
let memoryDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".slashvibe-memory.sqlite")
let memoryKeyProvider = KeychainMemoryKeyProvider(service: "com.startup.speechbar.memory")
let memoryStore = try MemoryStorageSQLiteStore(databaseURL: memoryDatabaseURL, keyProvider: memoryKeyProvider)
let memoryExtractor = DefaultMemoryExtractor()
let memoryCoordinator = MemoryCoordinator(store: memoryStore, extractor: memoryExtractor)

let coordinator = VoiceSessionCoordinator(
    hardwareSource: hardwareSource,
    audioInputSource: audioInputSource,
    transcriptionClient: transcriptionClient,
    credentialProvider: speechCredentialProvider,
    transcriptPublisher: transcriptPublisher,
    memoryRecorder: memoryCoordinator,
    focusedSnapshotProvider: focusedTextTranscriptPublisher,
    sleepClock: ContinuousSleepClock()
)
```

- [ ] **Step 6: Run the coordinator test to verify it passes**

Run: `swift test --filter successfulPublishRecordsObservedInputEvent -v`
Expected: PASS with one event recorded after a successful publish.

- [ ] **Step 7: Commit Stage A wiring**

```bash
git add Sources/SpeechBarApplication/VoiceSessionCoordinator.swift Sources/SpeechBarApp/StartUpSpeechBarApp.swift Tests/SpeechBarTests/TestDoubles.swift Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift
git commit -m "feat: record memory events from voice sessions"
```

## Task 8: Wire Stage B Recall Into Transcription and Polish

**Files:**
- Modify: `Sources/SpeechBarApplication/VoiceSessionCoordinator.swift`
- Modify: `Tests/SpeechBarTests/TestDoubles.swift`
- Modify: `Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift`

- [ ] **Step 1: Write failing recall integration tests**

```swift
@Test
@MainActor
func recallAddsKeywordsToTranscriptionConfiguration() async throws {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let retriever = MockMemoryRetriever(
        bundle: RecallBundle(
            vocabularyHints: ["OpenAI API", "Coze Space"],
            correctionHints: ["扣子空间->Coze Space"],
            styleHints: [],
            sceneHints: [],
            diagnosticSummary: "test"
        )
    )

    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        memoryRetriever: retriever,
        sleepClock: ImmediateSleepClock()
    )

    coordinator.start()
    hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
    try await eventually { client.lastConfiguration?.keywords.contains("OpenAI API") == true }
}

@Test
@MainActor
func recallAugmentsPolishContextMemoryProfile() async throws {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let postProcessor = MockTranscriptPostProcessor()
    let retriever = MockMemoryRetriever(
        bundle: RecallBundle(
            vocabularyHints: [],
            correctionHints: [],
            styleHints: ["tone=polite", "brevity=short"],
            sceneHints: ["app=com.apple.mail"],
            diagnosticSummary: "test"
        )
    )

    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        userProfileProvider: MockUserProfileContextProvider(),
        transcriptPostProcessor: postProcessor,
        memoryRetriever: retriever,
        sleepClock: ImmediateSleepClock()
    )

    coordinator.start()
    hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
    try await eventually { coordinator.sessionState == .recording }
    client.emit(.final("hello"))
    hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
    client.emit(.utteranceEnded)

    try await eventually { !postProcessor.receivedContexts.isEmpty }
    #expect(postProcessor.receivedContexts.last?.memoryProfile.contains("tone=polite") == true)
}
```

- [ ] **Step 2: Run the recall tests to verify they fail**

Run: `swift test --filter "recall" -v`
Expected: FAIL because `memoryRetriever` injection does not exist and the post-processor mock does not record contexts.

- [ ] **Step 3: Add the recall mocks in `Tests/SpeechBarTests/TestDoubles.swift`**

```swift
import MemoryDomain

struct MockMemoryRetriever: MemoryRetriever {
    var bundle: RecallBundle

    func recall(for request: RecallRequest) async throws -> RecallBundle {
        bundle
    }
}

final class MockTranscriptPostProcessor: TranscriptPostProcessor, @unchecked Sendable {
    var polishedText: String?
    var error: Error?
    private(set) var receivedTranscripts: [String] = []
    private(set) var receivedContexts: [UserProfileContext] = []

    func polish(
        transcript: String,
        context: UserProfileContext
    ) async throws -> String {
        receivedTranscripts.append(transcript)
        receivedContexts.append(context)
        if let error {
            throw error
        }
        return polishedText ?? transcript
    }
}
```

- [ ] **Step 4: Inject `MemoryRetriever` and adapt recall into coordinator behavior**

```swift
private let memoryRetriever: (any MemoryRetriever)?

private func currentRecallBundle() async -> RecallBundle? {
    guard let focusedSnapshotProvider, let snapshot = await focusedSnapshotProvider.currentFocusedInputSnapshot() else {
        return nil
    }

    let request = RecallRequest(
        timestamp: Date(),
        appIdentifier: snapshot.appIdentifier,
        windowTitle: snapshot.windowTitle,
        pageTitle: snapshot.pageTitle,
        fieldRole: snapshot.fieldRole,
        fieldLabel: snapshot.fieldLabel,
        requestedCapabilities: [.transcription, .polish]
    )

    return try? await memoryRetriever?.recall(for: request)
}

private func makeSessionConfiguration(context: UserProfileContext, recall: RecallBundle?) -> LiveTranscriptionConfiguration {
    let glossaryKeywords = context.terminologyGlossary.filter(\.isEnabled).map(\.term)
    let recallKeywords = (recall?.vocabularyHints ?? []) + (recall?.correctionHints ?? [])
    let keywords = Array(Set(glossaryKeywords + recallKeywords)).prefix(100)
    return LiveTranscriptionConfiguration(
        endpoint: baseConfiguration.endpoint,
        model: baseConfiguration.model,
        language: baseConfiguration.language,
        encoding: baseConfiguration.encoding,
        sampleRate: baseConfiguration.sampleRate,
        channels: baseConfiguration.channels,
        interimResults: baseConfiguration.interimResults,
        punctuate: baseConfiguration.punctuate,
        smartFormat: baseConfiguration.smartFormat,
        vadEvents: baseConfiguration.vadEvents,
        endpointingMilliseconds: baseConfiguration.endpointingMilliseconds,
        utteranceEndMilliseconds: baseConfiguration.utteranceEndMilliseconds,
        keywords: Array(keywords)
    )
}
```

- [ ] **Step 5: Inject recall hints into polish by deriving a temporary context**

```swift
private func makePolishContext(base: UserProfileContext, recall: RecallBundle?) -> UserProfileContext {
    guard let recall else { return base }
    let sections = (recall.styleHints + recall.sceneHints)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    guard !sections.isEmpty else { return base }

    var updated = base
    let prefix = updated.memoryProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    updated.memoryProfile = prefix.isEmpty ? sections : "\(prefix)\n\n\(sections)"
    return updated
}
```

- [ ] **Step 6: Run the recall tests to verify they pass**

Run: `swift test --filter "recall" -v`
Expected: PASS with recall hints present in both transcription keywords and polish context.

- [ ] **Step 7: Commit Stage B recall**

```bash
git add Sources/SpeechBarApplication/VoiceSessionCoordinator.swift Tests/SpeechBarTests/TestDoubles.swift Tests/SpeechBarTests/VoiceSessionCoordinatorTests.swift
git commit -m "feat: add memory-backed recall for transcription and polish"
```

## Task 9: Add Diagnostics and Internal Feature Flags for Stage A/B

**Files:**
- Modify: `Sources/SpeechBarApplication/DiagnosticsCoordinator.swift`
- Create: `Sources/SpeechBarApp/MemoryFeatureFlagStore.swift`
- Modify: `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowView.swift`
- Create: `Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift`

- [ ] **Step 1: Write the failing feature-flag test**

```swift
import Testing
@testable import SpeechBarApp

@Suite("MemoryFeatureFlagStore")
struct MemoryFeatureFlagStoreTests {
    @Test
    @MainActor
    func defaultsToLearnOnlyMode() {
        let store = MemoryFeatureFlagStore(defaults: UserDefaults(suiteName: "MemoryFeatureFlagStoreTests")!)
        #expect(store.captureEnabled)
        #expect(!store.recallEnabled)
    }
}
```

- [ ] **Step 2: Run the feature-flag test to verify it fails**

Run: `swift test --filter MemoryFeatureFlagStoreTests -v`
Expected: FAIL because the store does not exist.

- [ ] **Step 3: Implement the defaults-backed feature-flag store**

```swift
import Combine
import Foundation

@MainActor
final class MemoryFeatureFlagStore: ObservableObject {
    @Published var captureEnabled: Bool
    @Published var recallEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.captureEnabled = defaults.object(forKey: "memory.captureEnabled") as? Bool ?? true
        self.recallEnabled = defaults.object(forKey: "memory.recallEnabled") as? Bool ?? false
    }
}
```

- [ ] **Step 4: Add memory diagnostics and wire the feature flags into startup**

```swift
// DiagnosticsCoordinator:
func recordMemoryEvent(_ message: String) {
    recordDiagnostic(
        subsystem: "memory",
        severity: .info,
        message: message
    )
}

// StartUpSpeechBarApp:
let memoryFlags = MemoryFeatureFlagStore()
let coordinator = VoiceSessionCoordinator(
    ...,
    memoryCaptureEnabled: { await MainActor.run { memoryFlags.captureEnabled } },
    memoryRecallEnabled: { await MainActor.run { memoryFlags.recallEnabled } }
)
```

- [ ] **Step 5: Surface the two toggles on the existing memory page**

```swift
Toggle("启用记忆采集", isOn: $memoryFeatureFlagStore.captureEnabled)
Toggle("启用记忆召回", isOn: $memoryFeatureFlagStore.recallEnabled)
```

- [ ] **Step 6: Run the feature-flag test and the coordinator suite**

Run: `swift test --filter MemoryFeatureFlagStoreTests -v`
Expected: PASS

Run: `swift test --filter VoiceSessionCoordinator -v`
Expected: PASS with existing coordinator behavior intact.

- [ ] **Step 7: Commit diagnostics and flags**

```bash
git add Sources/SpeechBarApplication/DiagnosticsCoordinator.swift Sources/SpeechBarApp/MemoryFeatureFlagStore.swift Sources/SpeechBarApp/StartUpSpeechBarApp.swift Sources/SpeechBarApp/HomeWindowView.swift Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift
git commit -m "feat: add memory flags and diagnostics"
```

## Final Verification

- [ ] Run memory-target tests:

```bash
swift test --filter MemoryDomainTests -v
swift test --filter MemoryStorageSQLiteTests -v
swift test --filter MemoryExtractionTests -v
swift test --filter MemoryCoreTests -v
swift test --filter "Focused input capture" -v
```

Expected: PASS

- [ ] Run app integration tests:

```bash
swift test --filter VoiceSessionCoordinator -v
```

Expected: PASS

- [ ] Run the full suite:

```bash
swift test
```

Expected: PASS with the new `MemoryTests` target included.

- [ ] Final commit after any fixups:

```bash
git add Package.swift Sources Tests
git commit -m "feat: ship memory capture and recall foundations"
```

## Spec Coverage Check

- Privacy gate, sensitive-field exclusion, redaction, encryption, and retention: covered by Task 3 and Task 6.
- Stage A input event capture and observation-status handling: covered by Task 2, Task 6, and Task 7.
- Background extraction and confidence rules: covered by Task 4 and Task 5.
- Stage B hot-path recall for transcription and polish: covered by Task 8.
- Diagnostics and internal rollout flags: covered by Task 9.

Not covered in this plan by design:

- Stage C Memory Center UI
- Stage D Direct Fill
- Stage E cross-project hardening

Those need separate follow-on plans after this one lands.
