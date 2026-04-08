# Memory Constellation Main UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current form-heavy memory page with a calm, cluster-first Memory Constellation screen that renders live memory data, supports hover/focus/replay states, and keeps existing manual profile controls accessible as secondary configuration.

**Architecture:** Add a narrow memory-catalog query path so the app can read active memories without coupling the UI to storage details. Build the constellation as an app-layer presentation pipeline in `SpeechBarApp`: a derived display-model builder, a focused interaction store, and a set of small SwiftUI views for the header, toolbar, canvas, overlays, tray, and timeline. Keep the existing profile/glossary/toggle controls in a collapsed secondary section so the new relationship-first reading model stays primary while preserving the additive migration promised by the broader memory program.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Package Manager, Swift Testing (`import Testing`), existing `MemoryDomain` / `MemoryCore` / `MemoryStorageSQLite` targets, offscreen snapshot renderer in `SpeechBarApp`.

---

## Scope Decision

This plan covers one subsystem: the main Memory Constellation overview UI plus the minimal live-data plumbing it requires.

Included:

- live query access to active memories
- cluster / bridge / tray / timeline presentation models
- overview, cluster-hover, bridge-focus, and replay states
- privacy-safe and hidden presentation modes
- offscreen snapshot scenarios for visual QA
- preservation of current manual profile and glossary controls as secondary UI

Explicitly not included:

- browse/search/edit/hide/delete CRUD flows for the full Memory Center
- source-event inspection UI
- memory detail drawer beyond a stubbed future hook
- provenance deep dive

Those stay deferred, matching section 16 of the UI spec and Stage C follow-on work from the broader memory design.

## File Structure

### New Files

- `Sources/MemoryDomain/MemoryCenterQuery.swift`
  - Narrow UI-facing query type and catalog protocol for reading memories.
- `Sources/SpeechBarApp/MemoryConstellationTheme.swift`
  - Nocturnal palette, card/background modifiers, and focus-ring styling for the constellation surface.
- `Sources/SpeechBarApp/MemoryConstellationModels.swift`
  - Cluster, star, bridge, tray, timeline, filter, mode, and focus models.
- `Sources/SpeechBarApp/MemoryConstellationBuilder.swift`
  - Maps `MemoryItem` arrays into the derived display snapshot used by SwiftUI.
- `Sources/SpeechBarApp/MemoryConstellationStore.swift`
  - `@MainActor` observable store that loads memories and manages hover/focus/replay state.
- `Sources/SpeechBarApp/MemoryConstellationFixtures.swift`
  - Deterministic memory fixtures and a static catalog provider for tests and offscreen rendering.
- `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
  - Screen shell that composes the new constellation sections.
- `Sources/SpeechBarApp/MemoryConstellationHeaderView.swift`
  - Title, copy, status pills, and memory visibility control.
- `Sources/SpeechBarApp/MemoryConstellationToolbarView.swift`
  - Cluster filter chips and view-mode chips.
- `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
  - Cluster fields, stars, bridges, hover/focus interactions, and the floating guidance layer.
- `Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift`
  - Bridge story cards beneath the canvas.
- `Sources/SpeechBarApp/MemoryTimelineRibbonView.swift`
  - Passive/default ribbon plus replay selection affordances.
- `Sources/SpeechBarApp/MemoryProfileSettingsSection.swift`
  - Extracted version of the current profession/profile/glossary/toggle cards.
- `Tests/MemoryTests/MemoryCatalogTests.swift`
  - Unit coverage for the new memory catalog query contract.
- `Tests/SpeechBarTests/MemoryConstellationBuilderTests.swift`
  - Cluster/bridge/privacy/sparse-state mapping tests.
- `Tests/SpeechBarTests/MemoryConstellationStoreTests.swift`
  - Interaction-state transition tests.
- `Tests/SpeechBarTests/MemoryConstellationSnapshotCommandTests.swift`
  - Offscreen snapshot scenario parsing tests.
- `Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift`
  - SwiftUI smoke test for the integrated screen.
- `Tests/SpeechBarTests/MemoryConstellationAccessibilityTests.swift`
  - Hidden/privacy semantic summary tests.

### Existing Files To Modify

- `Sources/MemoryDomain/MemoryDomain.swift`
  - Make `MemoryType` and `MemoryStatus` enumerable and wire `MemoryStore` into the new catalog protocol.
- `Sources/MemoryCore/MemoryCore.swift`
  - Forward catalog queries through `MemoryCoordinator`.
- `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
  - Expose filtered memory listing for UI consumption.
- `Sources/SpeechBarApp/MemoryFeatureFlagStore.swift`
  - Persist the new display-mode state (`full`, `privacySafe`, `hidden`).
- `Sources/SpeechBarApp/HomeWindowView.swift`
  - Replace the existing `memoryPage` body with the new screen.
- `Sources/SpeechBarApp/HomeWindowStore.swift`
  - Update the memory-section subtitle so navigation matches the new screen identity.
- `Sources/SpeechBarApp/HomeWindowController.swift`
  - Own and inject the constellation store.
- `Sources/SpeechBarApp/StatusBarController.swift`
  - Forward the constellation store into the home window controller.
- `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`
  - Create the live constellation store from the memory coordinator and feature flags.
- `Sources/SpeechBarApp/OffscreenHomeSnapshot.swift`
  - Add memory scenario and display-mode overrides for visual QA renders.
- `Tests/MemoryTests/MemoryStorageSQLiteTests.swift`
  - Add query-level filtering tests.
- `Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift`
  - Cover display-mode defaults and persistence.

## Task 1: Expose a Live Memory Catalog Query for UI Work

**Files:**
- Create: `Sources/MemoryDomain/MemoryCenterQuery.swift`
- Modify: `Sources/MemoryDomain/MemoryDomain.swift`
- Modify: `Sources/MemoryCore/MemoryCore.swift`
- Modify: `Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift`
- Create: `Tests/MemoryTests/MemoryCatalogTests.swift`
- Modify: `Tests/MemoryTests/MemoryStorageSQLiteTests.swift`

- [ ] **Step 1: Write the failing catalog tests**

```swift
// Tests/MemoryTests/MemoryCatalogTests.swift
import Foundation
import Testing
import MemoryDomain
@testable import MemoryCore

@Suite("MemoryCatalog")
struct MemoryCatalogTests {
    @Test
    func defaultQueryTargetsActiveMemoriesAcrossAllTypes() {
        let query = MemoryCenterQuery()

        #expect(query.statuses == [.active])
        #expect(query.types == Set(MemoryType.allCases))
        #expect(query.limit == nil)
    }

    @Test
    func coordinatorForwardsCatalogQueriesToTheStore() async throws {
        let store = InMemoryCatalogStore(memories: [
            makeMemory(type: .vocabulary, payload: "OpenAI", status: .active),
            makeMemory(type: .style, payload: "brevity=short", status: .deleted)
        ])
        let coordinator = MemoryCoordinator(
            store: store,
            extractor: StaticMemoryExtractor(memories: [])
        )

        let rows = try await coordinator.listMemories(
            matching: MemoryCenterQuery(
                statuses: [.active],
                types: [.vocabulary],
                limit: 8
            )
        )

        #expect(rows.count == 1)
        #expect(rows[0].type == .vocabulary)
        #expect(rows[0].valueFingerprint == "OpenAI")
    }
}

private actor InMemoryCatalogStore: MemoryStore {
    private var memories: [MemoryItem]

    init(memories: [MemoryItem]) {
        self.memories = memories
    }

    func insert(event: InputEvent) async throws {}

    func upsert(memory: MemoryItem) async throws {
        memories.removeAll { $0.identityHash == memory.identityHash }
        memories.append(memory)
    }

    func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        memories
    }

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        let rows = memories.filter { query.statuses.contains($0.status) && query.types.contains($0.type) }
        if let limit = query.limit {
            return Array(rows.prefix(limit))
        }
        return rows
    }

    func markDeleted(identityHash: String, deletedAt: Date) async throws {}
}

private struct StaticMemoryExtractor: MemoryExtractor {
    let memories: [MemoryItem]

    func extract(from event: InputEvent) async throws -> [MemoryItem] {
        memories
    }
}

private func makeMemory(type: MemoryType, payload: String, status: MemoryStatus) -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: type,
        key: "\(type.rawValue):\(payload.lowercased())",
        valuePayload: Data(payload.utf8),
        valueFingerprint: payload,
        identityHash: "\(type.rawValue)|\(payload)|\(status.rawValue)",
        scope: .app("com.apple.mail"),
        confidence: 0.80,
        status: status,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        lastConfirmedAt: Date(timeIntervalSince1970: 0),
        sourceEventIDs: []
    )
}
```

```swift
// Add to Tests/MemoryTests/MemoryStorageSQLiteTests.swift
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MemoryCatalogTests -v`

Expected: FAIL with compile errors like `cannot find 'MemoryCenterQuery' in scope` and `value of type 'MemoryCoordinator' has no member 'listMemories'`.

- [ ] **Step 3: Add the query contract and storage plumbing**

```swift
// Sources/MemoryDomain/MemoryCenterQuery.swift
import Foundation

public struct MemoryCenterQuery: Sendable, Equatable {
    public let statuses: Set<MemoryStatus>
    public let types: Set<MemoryType>
    public let limit: Int?

    public init(
        statuses: Set<MemoryStatus> = [.active],
        types: Set<MemoryType> = Set(MemoryType.allCases),
        limit: Int? = nil
    ) {
        self.statuses = statuses
        self.types = types
        self.limit = limit
    }
}

public protocol MemoryCatalogProviding: Sendable {
    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem]
}
```

```swift
// Sources/MemoryDomain/MemoryDomain.swift
public enum MemoryType: String, Sendable, Codable, Equatable, CaseIterable {
    case vocabulary
    case correction
    case style
    case scene
}

public enum MemoryStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case active
    case hidden
    case deleted
}

public protocol MemoryStore: Sendable, MemoryCatalogProviding {
    func insert(event: InputEvent) async throws
    func upsert(memory: MemoryItem) async throws
    func listMemories(for request: RecallRequest) async throws -> [MemoryItem]
    func markDeleted(identityHash: String, deletedAt: Date) async throws
}
```

```swift
// Sources/MemoryCore/MemoryCore.swift
public actor MemoryCoordinator: MemoryRetriever, MemoryEventRecording, MemoryCatalogProviding {
    // existing properties and init stay the same

    public func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        try await store.listMemories(matching: query)
    }
}
```

```swift
// Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift
public actor MemoryStorageSQLiteStore: MemoryStore {
    public func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        let sql = """
        SELECT identity_hash, id, type, memory_key, value_payload, value_fingerprint,
               scope_kind, scope_app_identifier, scope_window_title, scope_field_role,
               scope_field_label, confidence, status, created_at, updated_at,
               last_confirmed_at, source_event_ids
        FROM memories
        ORDER BY updated_at DESC;
        """

        let rows = try self.query(sql, bind: { _ in }) { statement in
            let memory = try decodeMemory(from: statement)
            guard query.statuses.contains(memory.status) else { return nil }
            guard query.types.contains(memory.type) else { return nil }
            return memory
        }

        if let limit = query.limit {
            return Array(rows.prefix(limit))
        }
        return rows
    }

    public func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        try await listMemories(matching: MemoryCenterQuery()).filter { $0.scope.matches(request: request) }
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
}
```

- [ ] **Step 4: Rerun the catalog tests once the new query types exist**

Run: `swift test --filter MemoryCatalogTests -v`

Expected: PASS.

- [ ] **Step 5: Run the SQLite query test**

Run: `swift test --filter catalogQueryFiltersByStatusAndType -v`

Expected: PASS with the active vocabulary row returned and the deleted scene row excluded.

- [ ] **Step 6: Commit**

```bash
git add Sources/MemoryDomain/MemoryCenterQuery.swift Sources/MemoryDomain/MemoryDomain.swift Sources/MemoryCore/MemoryCore.swift Sources/MemoryStorageSQLite/MemoryStorageSQLite.swift Tests/MemoryTests/MemoryCatalogTests.swift Tests/MemoryTests/MemoryStorageSQLiteTests.swift
git commit -m "feat: expose memory catalog queries for ui"
```

## Task 2: Build the Constellation Display Models and Mapping Rules

**Files:**
- Create: `Sources/SpeechBarApp/MemoryConstellationModels.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationBuilder.swift`
- Create: `Tests/SpeechBarTests/MemoryConstellationBuilderTests.swift`

- [ ] **Step 1: Write the failing builder tests**

```swift
import Foundation
import Testing
import MemoryDomain
@testable import SpeechBarApp

@Suite("MemoryConstellationBuilder")
struct MemoryConstellationBuilderTests {
    @Test
    func correctionMemoriesJoinTheVocabularyCluster() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let sharedEvent = UUID()

        let snapshot = builder.build(
            memories: [
                makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [sharedEvent]),
                makeMemory(type: .correction, payload: "Coze Space", updatedAt: 100, eventIDs: [sharedEvent]),
                makeMemory(type: .style, payload: "brevity=short", updatedAt: 90, eventIDs: [sharedEvent]),
                makeMemory(type: .scene, payload: "AXTextArea", updatedAt: 80, eventIDs: [sharedEvent])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.clusters.map(\.kind) == [.vocabulary, .style, .scenes])
        #expect(snapshot.clusters.first(where: { $0.kind == .vocabulary })?.stars.count == 2)
    }

    @Test
    func privacySafeModeSuppressesRawTerms() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })

        let snapshot = builder.build(
            memories: [makeMemory(type: .vocabulary, payload: "Confidential Project Hera", updatedAt: 100, eventIDs: [UUID()])],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .privacySafe
        )

        #expect(snapshot.clusters[0].stars[0].label == "Protected memory")
        #expect(snapshot.relationshipCards[0].body.lowercased().contains("protected"))
    }

    @Test
    func noStrongBridgeFallsBackToEmergingThemesCopy() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })

        let snapshot = builder.build(
            memories: [
                makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [UUID()]),
                makeMemory(type: .style, payload: "brevity=short", updatedAt: 20, eventIDs: [UUID()])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.highlightedBridges.isEmpty)
        #expect(snapshot.guidanceCards.contains { $0.title == "Emerging Themes" })
    }
}

private func makeMemory(
    type: MemoryType,
    payload: String,
    updatedAt: TimeInterval,
    eventIDs: [UUID]
) -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: type,
        key: "\(type.rawValue):\(payload.lowercased())",
        valuePayload: Data(payload.utf8),
        valueFingerprint: payload,
        identityHash: "\(type.rawValue)|\(payload)|\(updatedAt)",
        scope: .app("com.apple.mail"),
        confidence: 0.80,
        status: .active,
        createdAt: Date(timeIntervalSince1970: updatedAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        lastConfirmedAt: Date(timeIntervalSince1970: updatedAt),
        sourceEventIDs: eventIDs
    )
}
```

- [ ] **Step 2: Run the builder tests to verify they fail**

Run: `swift test --filter MemoryConstellationBuilderTests -v`

Expected: FAIL with missing symbols such as `MemoryConstellationBuilder`, `MemoryConstellationClusterFilter`, `MemoryConstellationFocus`, and `MemoryConstellationDisplayMode`.

- [ ] **Step 3: Define the display models**

```swift
// Sources/SpeechBarApp/MemoryConstellationModels.swift
import Foundation

enum MemoryConstellationClusterKind: String, CaseIterable, Identifiable {
    case vocabulary
    case style
    case scenes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: return "Vocabulary"
        case .style: return "Style"
        case .scenes: return "Scenes"
        }
    }
}

enum MemoryConstellationClusterFilter: String, CaseIterable, Identifiable {
    case all
    case vocabulary
    case style
    case scenes

    var id: String { rawValue }
}

enum MemoryConstellationViewMode: String, CaseIterable, Identifiable {
    case clusterMap = "Cluster Map"
    case bridgeStories = "Bridge Stories"
    case timelineReplay = "Timeline Replay"

    var id: String { rawValue }
}

enum MemoryConstellationDisplayMode: String, CaseIterable {
    case full
    case privacySafe
    case hidden
}

enum MemoryConstellationFocus: Equatable {
    case overview
    case cluster(MemoryConstellationClusterKind)
    case bridge(UUID)
    case star(UUID)
}

struct MemoryConstellationSnapshot: Equatable {
    let title: String
    let subtitle: String
    let statusPills: [String]
    let clusters: [MemoryConstellationCluster]
    let highlightedBridges: [MemoryConstellationBridge]
    let guidanceCards: [MemoryConstellationGuidanceCard]
    let relationshipCards: [MemoryConstellationRelationshipCard]
    let timeline: MemoryConstellationTimeline
    let accessibilitySummary: String

    static let hidden = MemoryConstellationSnapshot(
        title: "My Universe",
        subtitle: "Memory visibility is hidden.",
        statusPills: ["Hidden"],
        clusters: [],
        highlightedBridges: [],
        guidanceCards: [],
        relationshipCards: [],
        timeline: .empty,
        accessibilitySummary: "Memory visibility is hidden. No constellation is shown."
    )
}

struct MemoryConstellationCluster: Identifiable, Equatable {
    let id: MemoryConstellationClusterKind
    let kind: MemoryConstellationClusterKind
    let stars: [MemoryConstellationStar]
    let itemCount: Int
    let emphasis: Double
    let isDimmed: Bool

    var title: String { kind.title }
}

struct MemoryConstellationStar: Identifiable, Equatable {
    let id: UUID
    let label: String
    let strength: Double
}

struct MemoryConstellationBridge: Identifiable, Equatable {
    let id: UUID
    let from: MemoryConstellationClusterKind
    let to: MemoryConstellationClusterKind
    let strength: Double
    let label: String
    let isFocused: Bool
}

struct MemoryConstellationGuidanceCard: Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
}

struct MemoryConstellationRelationshipCard: Identifiable, Equatable {
    let id: UUID
    let bridgeID: UUID?
    let title: String
    let body: String
}

struct MemoryConstellationTimeline: Equatable {
    let windows: [MemoryConstellationTimelineWindow]

    static let empty = MemoryConstellationTimeline(windows: [])
}

struct MemoryConstellationTimelineWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let memoryCount: Int
}
```

- [ ] **Step 4: Implement the builder**

```swift
// Sources/SpeechBarApp/MemoryConstellationBuilder.swift
import Foundation
import MemoryDomain

struct MemoryConstellationBuilder {
    let now: @Sendable () -> Date

    func build(
        memories: [MemoryItem],
        filter: MemoryConstellationClusterFilter,
        focus: MemoryConstellationFocus,
        viewMode: MemoryConstellationViewMode,
        displayMode: MemoryConstellationDisplayMode
    ) -> MemoryConstellationSnapshot {
        guard displayMode != .hidden else {
            return .hidden
        }

        let active = memories.filter { $0.status == .active }
        let filtered = active.filter { include($0, for: filter) }
        let grouped = Dictionary(grouping: filtered, by: clusterKind(for:))

        let clusters = MemoryConstellationClusterKind.allCases.compactMap { kind -> MemoryConstellationCluster? in
            let items = grouped[kind, default: []]
            guard !items.isEmpty else { return nil }
            return makeCluster(kind: kind, items: items, displayMode: displayMode, focus: focus)
        }

        let bridges = buildBridges(from: filtered, displayMode: displayMode, focus: focus)
        let relationshipCards = buildRelationshipCards(
            clusters: clusters,
            bridges: bridges,
            displayMode: displayMode
        )
        let guidanceCards = buildGuidanceCards(
            clusters: clusters,
            bridges: bridges
        )

        return MemoryConstellationSnapshot(
            title: "My Universe",
            subtitle: "Cluster mass first, then the bridge that matters now.",
            statusPills: [
                "30d local retention",
                "\(active.count) memories",
                displayMode == .privacySafe ? "Private View" : "Memory On"
            ],
            clusters: clusters,
            highlightedBridges: Array(bridges.prefix(2)),
            guidanceCards: guidanceCards,
            relationshipCards: relationshipCards,
            timeline: buildTimeline(from: filtered),
            accessibilitySummary: buildAccessibilitySummary(clusters: clusters, bridges: bridges, displayMode: displayMode)
        )
    }

    private func clusterKind(for memory: MemoryItem) -> MemoryConstellationClusterKind {
        switch memory.type {
        case .vocabulary, .correction:
            return .vocabulary
        case .style:
            return .style
        case .scene:
            return .scenes
        }
    }

    private func include(_ memory: MemoryItem, for filter: MemoryConstellationClusterFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .vocabulary:
            return clusterKind(for: memory) == .vocabulary
        case .style:
            return clusterKind(for: memory) == .style
        case .scenes:
            return clusterKind(for: memory) == .scenes
        }
    }

    private func buildBridges(
        from memories: [MemoryItem],
        displayMode: MemoryConstellationDisplayMode,
        focus: MemoryConstellationFocus
    ) -> [MemoryConstellationBridge] {
        var weights: [String: (UUID, UUID, Double)] = [:]
        let byEvent = Dictionary(grouping: memories.flatMap { memory in
            memory.sourceEventIDs.map { ($0, memory) }
        }, by: { $0.0 })

        for entries in byEvent.values {
            let uniqueMemories = entries.map { $0.1 }
            for lhs in uniqueMemories {
                for rhs in uniqueMemories where clusterKind(for: lhs) != clusterKind(for: rhs) {
                    let key = [clusterKind(for: lhs).rawValue, clusterKind(for: rhs).rawValue].sorted().joined(separator: "|")
                    let recency = max(lhs.updatedAt, rhs.updatedAt).timeIntervalSince1970 / 1000
                    let score = lhs.confidence + rhs.confidence + recency
                    weights[key] = (
                        lhs.id,
                        rhs.id,
                        max(weights[key]?.2 ?? 0, score)
                    )
                }
            }
        }

        return weights.sorted { $0.value.2 > $1.value.2 }.map { pair in
            let parts = pair.key.split(separator: "|").map(String.init)
            return MemoryConstellationBridge(
                id: UUID(),
                from: MemoryConstellationClusterKind(rawValue: parts[0])!,
                to: MemoryConstellationClusterKind(rawValue: parts[1])!,
                strength: pair.value.2,
                label: displayMode == .privacySafe ? "Protected relationship" : "Today's bridge",
                isFocused: false
            )
        }
    }

    private func makeCluster(
        kind: MemoryConstellationClusterKind,
        items: [MemoryItem],
        displayMode: MemoryConstellationDisplayMode,
        focus: MemoryConstellationFocus
    ) -> MemoryConstellationCluster {
        let stars = items.prefix(8).map { memory in
            MemoryConstellationStar(
                id: memory.id,
                label: displayMode == .privacySafe ? "Protected memory" : memory.valueFingerprint,
                strength: memory.confidence
            )
        }

        let isDimmed: Bool
        switch focus {
        case .overview:
            isDimmed = false
        case .cluster(let selected):
            isDimmed = selected != kind
        case .bridge:
            isDimmed = false
        case .star:
            isDimmed = false
        }

        return MemoryConstellationCluster(
            id: kind,
            kind: kind,
            stars: Array(stars),
            itemCount: items.count,
            emphasis: min(1.0, Double(items.count) / 6.0),
            isDimmed: isDimmed
        )
    }

    private func buildRelationshipCards(
        clusters: [MemoryConstellationCluster],
        bridges: [MemoryConstellationBridge],
        displayMode: MemoryConstellationDisplayMode
    ) -> [MemoryConstellationRelationshipCard] {
        guard !bridges.isEmpty else {
            return [
                MemoryConstellationRelationshipCard(
                    id: UUID(),
                    bridgeID: nil,
                    title: "Emerging Themes",
                    body: displayMode == .privacySafe
                        ? "Protected themes are forming, but no strong bridge is visible yet."
                        : "Themes are present, but no single bridge stands out yet."
                )
            ]
        }

        return bridges.prefix(3).enumerated().map { index, bridge in
            let title: String
            switch index {
            case 0: title = "Strongest Now"
            case 1: title = "Rising Bridge"
            default: title = "Subtle Link"
            }

            let body: String
            if displayMode == .privacySafe {
                body = "Protected relationship connecting \(bridge.from.title) and \(bridge.to.title)."
            } else {
                body = "\(bridge.from.title) is currently reinforcing \(bridge.to.title)."
            }

            return MemoryConstellationRelationshipCard(
                id: UUID(),
                bridgeID: bridge.id,
                title: title,
                body: body
            )
        }
    }

    private func buildGuidanceCards(
        clusters: [MemoryConstellationCluster],
        bridges: [MemoryConstellationBridge]
    ) -> [MemoryConstellationGuidanceCard] {
        if let bridge = bridges.first {
            return [
                MemoryConstellationGuidanceCard(
                    id: UUID(),
                    title: "Today's Bridge",
                    body: "\(bridge.from.title) is the clearest cross-theme relationship right now."
                ),
                MemoryConstellationGuidanceCard(
                    id: UUID(),
                    title: "Reading Cue",
                    body: "Hover a cluster before drilling into individual stars."
                )
            ]
        }

        return [
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "Emerging Themes",
                body: "Cluster mass is visible, but the strongest bridge is still forming."
            ),
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "Reading Cue",
                body: "Start with the largest cluster and then inspect smaller satellites."
            )
        ]
    }

    private func buildTimeline(from memories: [MemoryItem]) -> MemoryConstellationTimeline {
        let nowDate = now()
        let windows = [
            ("24h", "Today", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 24 * 60 * 60 }.count),
            ("7d", "7 Days", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 7 * 24 * 60 * 60 }.count),
            ("30d", "30 Days", memories.count)
        ]

        return MemoryConstellationTimeline(
            windows: windows.map { MemoryConstellationTimelineWindow(id: $0.0, title: $0.1, memoryCount: $0.2) }
        )
    }

    private func buildAccessibilitySummary(
        clusters: [MemoryConstellationCluster],
        bridges: [MemoryConstellationBridge],
        displayMode: MemoryConstellationDisplayMode
    ) -> String {
        switch displayMode {
        case .hidden:
            return "Memory visibility is hidden. No constellation is shown."
        case .privacySafe:
            return "Protected constellation view."
        case .full:
            return "Memory constellation ready."
        }
    }
}
```

- [ ] **Step 5: Run the builder tests to verify they pass**

Run: `swift test --filter MemoryConstellationBuilderTests -v`

Expected: PASS with cluster mapping, privacy-safe copy, and no-strong-bridge fallback covered.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpeechBarApp/MemoryConstellationModels.swift Sources/SpeechBarApp/MemoryConstellationBuilder.swift Tests/SpeechBarTests/MemoryConstellationBuilderTests.swift
git commit -m "feat: add memory constellation display mapping"
```

## Task 3: Add Interaction State and Persisted Display Modes

**Files:**
- Create: `Sources/SpeechBarApp/MemoryConstellationStore.swift`
- Modify: `Sources/SpeechBarApp/MemoryFeatureFlagStore.swift`
- Modify: `Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift`
- Create: `Tests/SpeechBarTests/MemoryConstellationStoreTests.swift`

- [ ] **Step 1: Write the failing store and feature-flag tests**

```swift
// Tests/SpeechBarTests/MemoryConstellationStoreTests.swift
import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationStore")
struct MemoryConstellationStoreTests {
    @Test
    @MainActor
    func hoverClusterTransitionsFromOverviewToClusterFocus() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.hover.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        store.hoverCluster(.vocabulary)

        #expect(store.focus == .cluster(.vocabulary))
        #expect(store.snapshot.relationshipCards.first?.body.contains("Vocabulary") == true)
    }

    @Test
    @MainActor
    func selectingReplayModeNarrowsTheTimelineWindow() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.replay.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        store.selectViewMode(.timelineReplay)
        store.selectTimelineWindow("7d")

        #expect(store.selectedViewMode == .timelineReplay)
        #expect(store.selectedTimelineWindowID == "7d")
    }
}

private struct InlineCatalogProvider: MemoryCatalogProviding {
    let memories: [MemoryItem]

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        memories
    }
}

private func sampleMemories() -> [MemoryItem] {
    let shared = UUID()
    return [
        MemoryItem(
            id: UUID(),
            type: .vocabulary,
            key: "vocabulary:openai",
            valuePayload: Data("OpenAI".utf8),
            valueFingerprint: "OpenAI",
            identityHash: "vocabulary|openai",
            scope: .app("com.apple.mail"),
            confidence: 0.80,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 80),
            updatedAt: Date(timeIntervalSince1970: 80),
            lastConfirmedAt: Date(timeIntervalSince1970: 80),
            sourceEventIDs: [shared]
        ),
        MemoryItem(
            id: UUID(),
            type: .style,
            key: "style:brevity",
            valuePayload: Data("brevity=short".utf8),
            valueFingerprint: "brevity=short",
            identityHash: "style|brevity",
            scope: .app("com.apple.mail"),
            confidence: 0.75,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 70),
            updatedAt: Date(timeIntervalSince1970: 70),
            lastConfirmedAt: Date(timeIntervalSince1970: 70),
            sourceEventIDs: [shared]
        )
    ]
}
```

```swift
// Add to Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift
@Test
@MainActor
func defaultsToFullDisplayModeAndPersistsChanges() {
    let suiteName = "MemoryFeatureFlagStoreTests.displayMode.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = MemoryFeatureFlagStore(defaults: defaults)
    #expect(store.displayMode == .full)

    store.displayMode = .privacySafe

    let reloaded = MemoryFeatureFlagStore(defaults: defaults)
    #expect(reloaded.displayMode == .privacySafe)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter MemoryConstellationStoreTests -v`

Expected: FAIL with missing `MemoryConstellationStore` and `displayMode`.

- [ ] **Step 3: Persist the display mode in the feature-flag store**

```swift
// Sources/SpeechBarApp/MemoryFeatureFlagStore.swift
@MainActor
final class MemoryFeatureFlagStore: ObservableObject {
    @Published var captureEnabled: Bool
    @Published var recallEnabled: Bool
    @Published var displayMode: MemoryConstellationDisplayMode

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.captureEnabled = defaults.object(forKey: Keys.captureEnabled) as? Bool ?? true
        self.recallEnabled = defaults.object(forKey: Keys.recallEnabled) as? Bool ?? false
        self.displayMode = defaults.string(forKey: Keys.displayMode)
            .flatMap(MemoryConstellationDisplayMode.init(rawValue:))
            ?? .full
        bindPersistence()
    }

    private func bindPersistence() {
        $captureEnabled.dropFirst().sink { [weak self] in self?.defaults.set($0, forKey: Keys.captureEnabled) }.store(in: &cancellables)
        $recallEnabled.dropFirst().sink { [weak self] in self?.defaults.set($0, forKey: Keys.recallEnabled) }.store(in: &cancellables)
        $displayMode.dropFirst().sink { [weak self] in self?.defaults.set($0.rawValue, forKey: Keys.displayMode) }.store(in: &cancellables)
    }
}

private enum Keys {
    static let captureEnabled = "memory.captureEnabled"
    static let recallEnabled = "memory.recallEnabled"
    static let displayMode = "memory.displayMode"
}
```

- [ ] **Step 4: Implement the interaction store**

```swift
// Sources/SpeechBarApp/MemoryConstellationStore.swift
import Foundation
import MemoryDomain

@MainActor
final class MemoryConstellationStore: ObservableObject {
    @Published private(set) var snapshot: MemoryConstellationSnapshot = .hidden
    @Published private(set) var focus: MemoryConstellationFocus = .overview
    @Published private(set) var selectedTimelineWindowID: String? = nil
    @Published private(set) var selectedFilter: MemoryConstellationClusterFilter = .all
    @Published private(set) var selectedViewMode: MemoryConstellationViewMode = .clusterMap

    private let catalog: (any MemoryCatalogProviding)?
    private let featureFlags: MemoryFeatureFlagStore
    private let builder: MemoryConstellationBuilder
    private var memories: [MemoryItem] = []

    init(
        catalog: (any MemoryCatalogProviding)?,
        featureFlags: MemoryFeatureFlagStore,
        builder: MemoryConstellationBuilder = MemoryConstellationBuilder(now: Date.init)
    ) {
        self.catalog = catalog
        self.featureFlags = featureFlags
        self.builder = builder
    }

    func reload() async {
        memories = (try? await catalog?.listMemories(matching: MemoryCenterQuery(limit: 200))) ?? []
        rebuildSnapshot()
    }

    func hoverCluster(_ cluster: MemoryConstellationClusterKind?) {
        focus = cluster.map(MemoryConstellationFocus.cluster) ?? .overview
        rebuildSnapshot()
    }

    func selectFilter(_ filter: MemoryConstellationClusterFilter) {
        selectedFilter = filter
        rebuildSnapshot()
    }

    func focusBridge(_ bridgeID: UUID?) {
        focus = bridgeID.map(MemoryConstellationFocus.bridge) ?? .overview
        rebuildSnapshot()
    }

    func selectViewMode(_ mode: MemoryConstellationViewMode) {
        selectedViewMode = mode
        if mode != .timelineReplay {
            selectedTimelineWindowID = nil
        }
        rebuildSnapshot()
    }

    func selectTimelineWindow(_ id: String?) {
        selectedTimelineWindowID = id
        rebuildSnapshot()
    }

    func refreshPresentation() {
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        snapshot = builder.build(
            memories: memories,
            filter: selectedFilter,
            focus: focus,
            viewMode: selectedViewMode,
            displayMode: featureFlags.displayMode
        )
    }
}
```

- [ ] **Step 5: Run the store and feature-flag tests**

Run: `swift test --filter MemoryConstellationStoreTests -v`

Expected: PASS.

Run: `swift test --filter defaultsToFullDisplayModeAndPersistsChanges -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpeechBarApp/MemoryFeatureFlagStore.swift Sources/SpeechBarApp/MemoryConstellationStore.swift Tests/SpeechBarTests/MemoryFeatureFlagStoreTests.swift Tests/SpeechBarTests/MemoryConstellationStoreTests.swift
git commit -m "feat: add constellation interaction state"
```

## Task 4: Add Deterministic Fixtures and Offscreen Snapshot Scenarios

**Files:**
- Create: `Sources/SpeechBarApp/MemoryConstellationFixtures.swift`
- Modify: `Sources/SpeechBarApp/OffscreenHomeSnapshot.swift`
- Create: `Tests/SpeechBarTests/MemoryConstellationSnapshotCommandTests.swift`

- [ ] **Step 1: Write the failing snapshot-command tests**

```swift
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationSnapshotCommand")
struct MemoryConstellationSnapshotCommandTests {
    @Test
    func parsesMemoryScenarioAndDisplayModeOverrides() {
        let command = OffscreenHomeSnapshotCommand.parse(arguments: [
            "SpeechBarApp",
            "--render-home-snapshot", "dist/offscreen-ui/home.png",
            "--section", "memory",
            "--memory-scenario", "privacy",
            "--memory-display-mode", "privacySafe"
        ])

        #expect(command?.memoryScenario == .privacy)
        #expect(command?.memoryDisplayMode == .privacySafe)
    }
}
```

- [ ] **Step 2: Run the snapshot-command tests to verify they fail**

Run: `swift test --filter MemoryConstellationSnapshotCommandTests -v`

Expected: FAIL with missing `memoryScenario` and `memoryDisplayMode` properties on `OffscreenHomeSnapshotCommand`.

- [ ] **Step 3: Add reusable fixtures and a static catalog provider**

```swift
// Sources/SpeechBarApp/MemoryConstellationFixtures.swift
import Foundation
import MemoryDomain

enum MemoryConstellationFixtures {
    static func defaultMemories(now: Date) -> [MemoryItem] {
        let bridgeA = UUID()
        let bridgeB = UUID()

        return [
            makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: now.addingTimeInterval(-300), eventIDs: [bridgeA]),
            makeMemory(type: .correction, payload: "Coze Space", updatedAt: now.addingTimeInterval(-280), eventIDs: [bridgeA]),
            makeMemory(type: .style, payload: "brevity=short", updatedAt: now.addingTimeInterval(-260), eventIDs: [bridgeA]),
            makeMemory(type: .scene, payload: "AXTextArea", updatedAt: now.addingTimeInterval(-240), eventIDs: [bridgeA]),
            makeMemory(type: .vocabulary, payload: "vector database", updatedAt: now.addingTimeInterval(-120), eventIDs: [bridgeB]),
            makeMemory(type: .scene, payload: "AXSearchField", updatedAt: now.addingTimeInterval(-100), eventIDs: [bridgeB])
        ]
    }

    static func sparseMemories(now: Date) -> [MemoryItem] {
        [makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: now.addingTimeInterval(-300), eventIDs: [UUID()])]
    }

    static func privacyMemories(now: Date) -> [MemoryItem] {
        defaultMemories(now: now)
    }

    static func dominantMemories(now: Date) -> [MemoryItem] {
        let anchor = UUID()
        return [
            makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: now.addingTimeInterval(-300), eventIDs: [anchor]),
            makeMemory(type: .vocabulary, payload: "vector database", updatedAt: now.addingTimeInterval(-280), eventIDs: [anchor]),
            makeMemory(type: .correction, payload: "Coze Space", updatedAt: now.addingTimeInterval(-260), eventIDs: [anchor]),
            makeMemory(type: .style, payload: "brevity=short", updatedAt: now.addingTimeInterval(-180), eventIDs: [anchor]),
            makeMemory(type: .scene, payload: "AXTextArea", updatedAt: now.addingTimeInterval(-120), eventIDs: [UUID()])
        ]
    }

    static func noBridgeMemories(now: Date) -> [MemoryItem] {
        [
            makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: now.addingTimeInterval(-300), eventIDs: [UUID()]),
            makeMemory(type: .style, payload: "brevity=short", updatedAt: now.addingTimeInterval(-200), eventIDs: [UUID()]),
            makeMemory(type: .scene, payload: "AXTextArea", updatedAt: now.addingTimeInterval(-100), eventIDs: [UUID()])
        ]
    }
}

private func makeMemory(
    type: MemoryType,
    payload: String,
    updatedAt: Date,
    eventIDs: [UUID]
) -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: type,
        key: "\(type.rawValue):\(payload.lowercased())",
        valuePayload: Data(payload.utf8),
        valueFingerprint: payload,
        identityHash: "\(type.rawValue)|\(payload)|\(updatedAt.timeIntervalSince1970)",
        scope: .app("com.apple.mail"),
        confidence: 0.80,
        status: .active,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        lastConfirmedAt: updatedAt,
        sourceEventIDs: eventIDs
    )
}

struct StaticMemoryCatalogProvider: MemoryCatalogProviding {
    let memories: [MemoryItem]

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        let rows = memories.filter { query.statuses.contains($0.status) && query.types.contains($0.type) }
        if let limit = query.limit {
            return Array(rows.prefix(limit))
        }
        return rows
    }
}
```

- [ ] **Step 4: Add scenario parsing and snapshot-environment wiring**

```swift
// Sources/SpeechBarApp/OffscreenHomeSnapshot.swift
struct OffscreenHomeSnapshotCommand: Sendable {
    let outputURL: URL
    let section: SectionOverride?
    let theme: ThemeOverride?
    let memoryScenario: MemoryScenario
    let memoryDisplayMode: MemoryConstellationDisplayMode?
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat

    enum MemoryScenario: String, Sendable {
        case live
        case `default`
        case sparse
        case privacy
        case dominant
        case noBridge
    }

    static func parse(arguments: [String]) -> Self? {
        // existing parsing stays in place
        let memoryScenario = value(after: "--memory-scenario")
            .flatMap(MemoryScenario.init(rawValue:))
            ?? .default
        let memoryDisplayMode = value(after: "--memory-display-mode")
            .flatMap(MemoryConstellationDisplayMode.init(rawValue:))

        return Self(
            outputURL: outputURL,
            section: section,
            theme: theme,
            memoryScenario: memoryScenario,
            memoryDisplayMode: memoryDisplayMode,
            width: CGFloat(width),
            height: CGFloat(height),
            scale: CGFloat(scale)
        )
    }
}

@MainActor
private final class SnapshotEnvironment {
    let memoryConstellationStore: MemoryConstellationStore

    init(defaults: UserDefaults, command: OffscreenHomeSnapshotCommand) {
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        if let override = command.memoryDisplayMode {
            featureFlags.displayMode = override
        }

        let provider: (any MemoryCatalogProviding)? = switch command.memoryScenario {
        case .live:
            nil
        case .default:
            StaticMemoryCatalogProvider(memories: MemoryConstellationFixtures.defaultMemories(now: Date(timeIntervalSince1970: 100)))
        case .sparse:
            StaticMemoryCatalogProvider(memories: MemoryConstellationFixtures.sparseMemories(now: Date(timeIntervalSince1970: 100)))
        case .privacy:
            StaticMemoryCatalogProvider(memories: MemoryConstellationFixtures.privacyMemories(now: Date(timeIntervalSince1970: 100)))
        case .dominant:
            StaticMemoryCatalogProvider(memories: MemoryConstellationFixtures.dominantMemories(now: Date(timeIntervalSince1970: 100)))
        case .noBridge:
            StaticMemoryCatalogProvider(memories: MemoryConstellationFixtures.noBridgeMemories(now: Date(timeIntervalSince1970: 100)))
        }

        self.memoryConstellationStore = MemoryConstellationStore(
            catalog: provider,
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )
    }
}
```

- [ ] **Step 5: Run the snapshot-command tests**

Run: `swift test --filter MemoryConstellationSnapshotCommandTests -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpeechBarApp/MemoryConstellationFixtures.swift Sources/SpeechBarApp/OffscreenHomeSnapshot.swift Tests/SpeechBarTests/MemoryConstellationSnapshotCommandTests.swift
git commit -m "feat: add constellation snapshot scenarios"
```

## Task 5: Compose the New UI and Integrate It Into the Memory Page

**Files:**
- Create: `Sources/SpeechBarApp/MemoryConstellationTheme.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationHeaderView.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationToolbarView.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
- Create: `Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift`
- Create: `Sources/SpeechBarApp/MemoryTimelineRibbonView.swift`
- Create: `Sources/SpeechBarApp/MemoryProfileSettingsSection.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowView.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowStore.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowController.swift`
- Modify: `Sources/SpeechBarApp/StatusBarController.swift`
- Modify: `Sources/SpeechBarApp/StartUpSpeechBarApp.swift`

- [ ] **Step 1: Write a failing smoke test for the integrated screen**

```swift
import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationScreen")
struct MemoryConstellationScreenSmokeTests {
    @Test
    @MainActor
    func screenBuildsFromFixtureData() async {
        let suiteName = "MemoryConstellationScreenSmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let constellationStore = MemoryConstellationStore(
            catalog: StaticMemoryCatalogProvider(
                memories: MemoryConstellationFixtures.defaultMemories(now: Date(timeIntervalSince1970: 100))
            ),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )
        await constellationStore.reload()

        let screen = MemoryConstellationScreen(
            constellationStore: constellationStore,
            userProfileStore: UserProfileStore(defaults: defaults),
            memoryFeatureFlagStore: featureFlags
        )

        #expect(String(describing: type(of: screen.body)).isEmpty == false)
    }
}
```

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `swift test --filter MemoryConstellationScreenSmokeTests -v`

Expected: FAIL with missing `MemoryConstellationScreen`.

- [ ] **Step 3: Build the theme and shell views**

```swift
// Sources/SpeechBarApp/MemoryConstellationTheme.swift
import SwiftUI

struct MemoryConstellationTheme {
    let background = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.04, blue: 0.08),
            Color(red: 0.05, green: 0.07, blue: 0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    let vocabulary = Color(red: 0.36, green: 0.58, blue: 0.92)
    let style = Color(red: 0.80, green: 0.45, blue: 0.58)
    let scenes = Color(red: 0.39, green: 0.68, blue: 0.56)
    let bridge = Color(red: 0.93, green: 0.76, blue: 0.37)
    let text = Color(red: 0.96, green: 0.94, blue: 0.90)
    let mutedText = Color(red: 0.69, green: 0.72, blue: 0.78)
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationScreen.swift
import SwiftUI

struct MemoryConstellationScreen: View {
    @ObservedObject var constellationStore: MemoryConstellationStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore

    private let theme = MemoryConstellationTheme()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MemoryConstellationHeaderView(
                snapshot: constellationStore.snapshot,
                displayMode: $memoryFeatureFlagStore.displayMode,
                theme: theme
            )
            MemoryConstellationToolbarView(
                selectedFilter: Binding(
                    get: { constellationStore.selectedFilter },
                    set: { constellationStore.selectFilter($0) }
                ),
                selectedViewMode: Binding(
                    get: { constellationStore.selectedViewMode },
                    set: { constellationStore.selectViewMode($0) }
                ),
                theme: theme
            )
            ZStack(alignment: .topLeading) {
                MemoryConstellationCanvasView(
                    store: constellationStore,
                    theme: theme
                )
            }
            MemoryConstellationRelationshipTrayView(
                cards: constellationStore.snapshot.relationshipCards,
                theme: theme
            ) { bridgeID in
                constellationStore.focusBridge(bridgeID)
            }
            MemoryTimelineRibbonView(
                timeline: constellationStore.snapshot.timeline,
                selectedWindowID: constellationStore.selectedTimelineWindowID,
                theme: theme
            ) { windowID in
                constellationStore.selectTimelineWindow(windowID)
            }
            DisclosureGroup("Manual profile & learning controls") {
                MemoryProfileSettingsSection(
                    userProfileStore: userProfileStore,
                    memoryFeatureFlagStore: memoryFeatureFlagStore
                )
                .padding(.top, 12)
            }
            .foregroundStyle(theme.text)
        }
        .padding(24)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .task {
            await constellationStore.reload()
        }
        .onChange(of: memoryFeatureFlagStore.displayMode) { _, _ in
            constellationStore.refreshPresentation()
        }
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationHeaderView.swift
import SwiftUI

struct MemoryConstellationHeaderView: View {
    let snapshot: MemoryConstellationSnapshot
    @Binding var displayMode: MemoryConstellationDisplayMode
    let theme: MemoryConstellationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.text)
            Text(snapshot.subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.mutedText)

            HStack(spacing: 10) {
                ForEach(snapshot.statusPills, id: \.self) { pill in
                    Text(pill)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(theme.text)
                }

                Picker("Display Mode", selection: $displayMode) {
                    Text("Visible").tag(MemoryConstellationDisplayMode.full)
                    Text("Private").tag(MemoryConstellationDisplayMode.privacySafe)
                    Text("Hidden").tag(MemoryConstellationDisplayMode.hidden)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }
        }
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationToolbarView.swift
import SwiftUI

struct MemoryConstellationToolbarView: View {
    @Binding var selectedFilter: MemoryConstellationClusterFilter
    @Binding var selectedViewMode: MemoryConstellationViewMode
    let theme: MemoryConstellationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(MemoryConstellationClusterFilter.allCases) { filter in
                    Button(filter.rawValue.capitalized) {
                        selectedFilter = filter
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedFilter == filter ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(theme.text)
                }
            }

            HStack(spacing: 10) {
                ForEach(MemoryConstellationViewMode.allCases) { mode in
                    Button(mode.rawValue) {
                        selectedViewMode = mode
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedViewMode == mode ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(theme.mutedText)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build the canvas, tray, timeline, and extracted settings section**

```swift
// Sources/SpeechBarApp/MemoryConstellationCanvasView.swift
import SwiftUI

struct MemoryConstellationCanvasView: View {
    @ObservedObject var store: MemoryConstellationStore
    let theme: MemoryConstellationTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.03))

            ForEach(store.snapshot.clusters) { cluster in
                Button {
                    store.hoverCluster(cluster.kind)
                } label: {
                    ClusterFieldView(cluster: cluster, theme: theme)
                }
                .buttonStyle(.plain)
            }

            ForEach(store.snapshot.highlightedBridges) { bridge in
                Button {
                    store.focusBridge(bridge.id)
                } label: {
                    BridgeHighlightView(bridge: bridge, theme: theme)
                }
                .buttonStyle(.plain)
            }

            if let guidance = store.snapshot.guidanceCards.first {
                VStack {
                    HStack {
                        GuidanceCardView(card: guidance, theme: theme)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(18)
            }
        }
        .frame(minHeight: 420)
    }
}

private struct ClusterFieldView: View {
    let cluster: MemoryConstellationCluster
    let theme: MemoryConstellationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cluster.kind.title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(cluster.itemCount) memories")
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedText)
            HStack(spacing: 6) {
                ForEach(cluster.stars.prefix(4)) { star in
                    Circle()
                        .fill(theme.text.opacity(max(0.35, star.strength)))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Color.white.opacity(cluster.isDimmed ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(theme.text)
    }
}

private struct BridgeHighlightView: View {
    let bridge: MemoryConstellationBridge
    let theme: MemoryConstellationTheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text(bridge.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bridge.opacity(0.20), in: Capsule())
        .foregroundStyle(theme.bridge)
    }
}

private struct GuidanceCardView: View {
    let card: MemoryConstellationGuidanceCard
    let theme: MemoryConstellationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.bridge)
            Text(card.body)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift
import SwiftUI

struct MemoryConstellationRelationshipTrayView: View {
    let cards: [MemoryConstellationRelationshipCard]
    let theme: MemoryConstellationTheme
    let onSelect: (UUID?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards) { card in
                Button {
                    onSelect(card.bridgeID)
                } label: {
                    RelationshipCardView(card: card, theme: theme)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RelationshipCardView: View {
    let card: MemoryConstellationRelationshipCard
    let theme: MemoryConstellationTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.bridge)
            Text(card.body)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryTimelineRibbonView.swift
import SwiftUI

struct MemoryTimelineRibbonView: View {
    let timeline: MemoryConstellationTimeline
    let selectedWindowID: String?
    let theme: MemoryConstellationTheme
    let onSelect: (String?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(timeline.windows) { window in
                Button {
                    onSelect(window.id)
                } label: {
                    VStack(spacing: 4) {
                        Text(window.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(window.memoryCount)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(selectedWindowID == window.id ? Color.white.opacity(0.14) : Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(theme.text)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryProfileSettingsSection.swift
import SwiftUI

struct MemoryProfileSettingsSection: View {
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keep manual profile configuration below the constellation so learned memory stays primary.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Toggle("Enable memory capture", isOn: $memoryFeatureFlagStore.captureEnabled)
            Toggle("Enable memory recall", isOn: $memoryFeatureFlagStore.recallEnabled)

            TextField("Profession", text: $userProfileStore.profession)
                .textFieldStyle(.roundedBorder)

            PlaceholderTextEditor(
                text: $userProfileStore.memoryProfile,
                placeholder: "Describe your background, recurring scenes, and writing preferences."
            )
            .frame(minHeight: 220)
        }
    }
}
```

- [ ] **Step 5: Wire the screen into the app entry points**

```swift
// Sources/SpeechBarApp/StartUpSpeechBarApp.swift
let memoryConstellationStore = MemoryConstellationStore(
    catalog: memoryCoordinator,
    featureFlags: memoryFeatureFlagStore,
    builder: MemoryConstellationBuilder(now: Date.init)
)

self.statusBarController = StatusBarController(
    coordinator: coordinator,
    agentMonitorCoordinator: agentMonitorCoordinator,
    embeddedDisplayCoordinator: embeddedDisplayCoordinator,
    diagnosticsCoordinator: diagnosticsCoordinator,
    pushToTalkSource: pushToTalkSource,
    userProfileStore: userProfileStore,
    audioInputSettingsStore: audioInputSettingsStore,
    modelSettingsStore: modelSettingsStore,
    localWhisperModelStore: localWhisperModelStore,
    senseVoiceModelStore: senseVoiceModelStore,
    memoryFeatureFlagStore: memoryFeatureFlagStore,
    memoryConstellationStore: memoryConstellationStore
)
```

```swift
// Sources/SpeechBarApp/StatusBarController.swift
init(
    coordinator: VoiceSessionCoordinator,
    agentMonitorCoordinator: AgentMonitorCoordinator,
    embeddedDisplayCoordinator: EmbeddedDisplayCoordinator,
    diagnosticsCoordinator: DiagnosticsCoordinator,
    pushToTalkSource: OnScreenPushToTalkSource,
    userProfileStore: UserProfileStore,
    audioInputSettingsStore: AudioInputSettingsStore,
    modelSettingsStore: OpenAIModelSettingsStore,
    localWhisperModelStore: LocalWhisperModelStore,
    senseVoiceModelStore: SenseVoiceModelStore,
    memoryFeatureFlagStore: MemoryFeatureFlagStore,
    memoryConstellationStore: MemoryConstellationStore
) {
    self.homeWindowController = HomeWindowController(
        coordinator: coordinator,
        agentMonitorCoordinator: agentMonitorCoordinator,
        embeddedDisplayCoordinator: embeddedDisplayCoordinator,
        diagnosticsCoordinator: diagnosticsCoordinator,
        pushToTalkSource: pushToTalkSource,
        userProfileStore: userProfileStore,
        audioInputSettingsStore: audioInputSettingsStore,
        modelSettingsStore: modelSettingsStore,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore,
        memoryFeatureFlagStore: memoryFeatureFlagStore,
        memoryConstellationStore: memoryConstellationStore
    )
}
```

```swift
// Sources/SpeechBarApp/HomeWindowController.swift
private let memoryConstellationStore: MemoryConstellationStore

init(
    coordinator: VoiceSessionCoordinator,
    agentMonitorCoordinator: AgentMonitorCoordinator,
    embeddedDisplayCoordinator: EmbeddedDisplayCoordinator,
    diagnosticsCoordinator: DiagnosticsCoordinator,
    pushToTalkSource: OnScreenPushToTalkSource,
    userProfileStore: UserProfileStore,
    audioInputSettingsStore: AudioInputSettingsStore,
    modelSettingsStore: OpenAIModelSettingsStore,
    localWhisperModelStore: LocalWhisperModelStore,
    senseVoiceModelStore: SenseVoiceModelStore,
    memoryFeatureFlagStore: MemoryFeatureFlagStore,
    memoryConstellationStore: MemoryConstellationStore
) {
    self.memoryConstellationStore = memoryConstellationStore
    let hostingController = NSHostingController(
        rootView: HomeWindowView(
            coordinator: coordinator,
            agentMonitorCoordinator: agentMonitorCoordinator,
            embeddedDisplayCoordinator: embeddedDisplayCoordinator,
            diagnosticsCoordinator: diagnosticsCoordinator,
            store: store,
            userProfileStore: userProfileStore,
            audioInputSettingsStore: audioInputSettingsStore,
            modelSettingsStore: modelSettingsStore,
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore,
            memoryFeatureFlagStore: memoryFeatureFlagStore,
            memoryConstellationStore: memoryConstellationStore,
            pushToTalkSource: pushToTalkSource
        )
    )
}
```

```swift
// Sources/SpeechBarApp/HomeWindowView.swift
@ObservedObject var memoryConstellationStore: MemoryConstellationStore

private var memoryPage: some View {
    MemoryConstellationScreen(
        constellationStore: memoryConstellationStore,
        userProfileStore: userProfileStore,
        memoryFeatureFlagStore: memoryFeatureFlagStore
    )
}
```

```swift
// Sources/SpeechBarApp/HomeWindowStore.swift
case .memory:
    return "关系星图"
```

```swift
// Sources/SpeechBarApp/OffscreenHomeSnapshot.swift
let rootView = HomeWindowView(
    coordinator: environment.coordinator,
    agentMonitorCoordinator: environment.agentMonitorCoordinator,
    embeddedDisplayCoordinator: environment.embeddedDisplayCoordinator,
    diagnosticsCoordinator: environment.diagnosticsCoordinator,
    store: environment.homeStore,
    userProfileStore: environment.userProfileStore,
    audioInputSettingsStore: environment.audioInputSettingsStore,
    modelSettingsStore: environment.modelSettingsStore,
    localWhisperModelStore: environment.localWhisperModelStore,
    senseVoiceModelStore: environment.senseVoiceModelStore,
    memoryFeatureFlagStore: environment.memoryFeatureFlagStore,
    memoryConstellationStore: environment.memoryConstellationStore,
    pushToTalkSource: environment.pushToTalkSource
)
```

- [ ] **Step 6: Build the app and run the smoke test**

Run: `swift test --filter MemoryConstellationScreenSmokeTests -v`

Expected: PASS.

Run: `swift build -c debug --product SpeechBarApp`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/SpeechBarApp/MemoryConstellationTheme.swift Sources/SpeechBarApp/MemoryConstellationScreen.swift Sources/SpeechBarApp/MemoryConstellationHeaderView.swift Sources/SpeechBarApp/MemoryConstellationToolbarView.swift Sources/SpeechBarApp/MemoryConstellationCanvasView.swift Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift Sources/SpeechBarApp/MemoryTimelineRibbonView.swift Sources/SpeechBarApp/MemoryProfileSettingsSection.swift Sources/SpeechBarApp/HomeWindowView.swift Sources/SpeechBarApp/HomeWindowStore.swift Sources/SpeechBarApp/HomeWindowController.swift Sources/SpeechBarApp/StatusBarController.swift Sources/SpeechBarApp/StartUpSpeechBarApp.swift Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift
git commit -m "feat: integrate memory constellation screen"
```

## Task 6: Add Accessibility, Reduced-Motion, and Fail-Closed Semantics

**Files:**
- Modify: `Sources/SpeechBarApp/MemoryConstellationModels.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationBuilder.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
- Create: `Tests/SpeechBarTests/MemoryConstellationAccessibilityTests.swift`

- [ ] **Step 1: Write the failing accessibility tests**

```swift
import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationAccessibility")
struct MemoryConstellationAccessibilityTests {
    @Test
    func hiddenModeFailsClosed() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let snapshot = builder.build(
            memories: MemoryConstellationFixtures.defaultMemories(now: Date(timeIntervalSince1970: 100)),
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .hidden
        )

        #expect(snapshot.clusters.isEmpty)
        #expect(snapshot.relationshipCards.isEmpty)
        #expect(snapshot.accessibilitySummary == "Memory visibility is hidden. No constellation is shown.")
    }

    @Test
    func privacySafeModeUsesGenericNarration() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let snapshot = builder.build(
            memories: MemoryConstellationFixtures.privacyMemories(now: Date(timeIntervalSince1970: 100)),
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .privacySafe
        )

        #expect(snapshot.accessibilitySummary.lowercased().contains("protected"))
        #expect(!snapshot.accessibilitySummary.contains("OpenAI"))
    }
}
```

- [ ] **Step 2: Run the accessibility tests to verify they fail**

Run: `swift test --filter MemoryConstellationAccessibilityTests -v`

Expected: FAIL because the snapshot does not yet guarantee hidden-mode semantics or a dedicated accessibility summary.

- [ ] **Step 3: Add semantic summaries and reduced-motion hooks**

```swift
// Sources/SpeechBarApp/MemoryConstellationBuilder.swift
private func buildAccessibilitySummary(
    clusters: [MemoryConstellationCluster],
    bridges: [MemoryConstellationBridge],
    displayMode: MemoryConstellationDisplayMode
) -> String {
    switch displayMode {
    case .hidden:
        return "Memory visibility is hidden. No constellation is shown."
    case .privacySafe:
        if let bridge = bridges.first {
            return "Protected constellation view. Main themes are \(clusters.map(\.title).joined(separator: ", ")). Strongest protected bridge connects \(bridge.from.title) and \(bridge.to.title)."
        }
        return "Protected constellation view. Themes are visible without raw memory terms."
    case .full:
        if let bridge = bridges.first {
            return "Main themes are \(clusters.map(\.title).joined(separator: ", ")). Strongest bridge connects \(bridge.from.title) and \(bridge.to.title)."
        }
        return "Main themes are \(clusters.map(\.title).joined(separator: ", ")). No strong bridge is active today."
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationCanvasView.swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    ZStack {
        // existing canvas content
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.focus)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(store.snapshot.accessibilitySummary)
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift
struct MemoryConstellationRelationshipTrayView: View {
    let cards: [MemoryConstellationRelationshipCard]
    let theme: MemoryConstellationTheme
    let onSelect: (UUID?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards) { card in
                Button {
                    onSelect(card.bridgeID)
                } label: {
                    RelationshipCardView(card: card, theme: theme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.title). \(card.body)")
            }
        }
    }
}
```

- [ ] **Step 4: Run the accessibility tests again**

Run: `swift test --filter MemoryConstellationAccessibilityTests -v`

Expected: PASS.

- [ ] **Step 5: Render the privacy and hidden visual states**

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario privacy --memory-display-mode privacySafe`

Expected: a PNG render is written under `dist/offscreen-ui/...` and the OCR summary is generated.

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario default --memory-display-mode hidden`

Expected: a PNG render is written with the fail-closed hidden state and no exposed memory terms.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpeechBarApp/MemoryConstellationModels.swift Sources/SpeechBarApp/MemoryConstellationBuilder.swift Sources/SpeechBarApp/MemoryConstellationCanvasView.swift Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift Sources/SpeechBarApp/MemoryConstellationScreen.swift Tests/SpeechBarTests/MemoryConstellationAccessibilityTests.swift
git commit -m "feat: polish constellation accessibility"
```

## Task 7: Final Verification and Visual QA Sweep

**Files:**
- Modify: `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationHeaderView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationToolbarView.swift`
- Modify: `Sources/SpeechBarApp/MemoryTimelineRibbonView.swift`

- [ ] **Step 1: Run the full package test suite**

Run: `swift test`

Expected: PASS across `MemoryTests` and `SpeechBarTests`.

- [ ] **Step 2: Render the four required visual QA scenarios**

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario default`

Expected: default overview render with clear cluster masses, one gold bridge, tray, and passive timeline ribbon.

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario sparse`

Expected: sparse render with fewer clusters, more spacing, and explanatory guidance instead of fake density.

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario noBridge`

Expected: no highlighted gold bridge and `Emerging Themes` guidance copy.

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario dominant`

Expected: one dominant cluster remains primary while smaller clusters stay visible as satellites.

- [ ] **Step 3: Fix any remaining spacing, contrast, or focus-ring regressions found in the renders**

```swift
// Apply only the minimal visual polish discovered during the render sweep.
// Likely touch points:
// - MemoryConstellationHeaderView.swift
// - MemoryConstellationToolbarView.swift
// - MemoryConstellationCanvasView.swift
// - MemoryTimelineRibbonView.swift
```

- [ ] **Step 4: Re-run the exact command that exposed the regression**

Run: `./Scripts/render_offscreen_snapshot.sh --section memory --memory-scenario default`

Expected: the corrected render shows readable text contrast, clear keyboard focus indication, and no overlap between guidance cards and the canvas.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpeechBarApp/MemoryConstellationCanvasView.swift Sources/SpeechBarApp/MemoryConstellationHeaderView.swift Sources/SpeechBarApp/MemoryConstellationToolbarView.swift Sources/SpeechBarApp/MemoryTimelineRibbonView.swift
git commit -m "fix: finalize constellation ui polish"
```

## Self-Review

### Spec Coverage

- Header, toolbar, canvas, floating guidance, tray, and passive timeline ribbon are covered by Task 5.
- Default overview, hover-cluster, bridge-focus, and replay states are covered by Tasks 2, 3, and 5.
- Nocturnal visual language, restrained gold-bridge emphasis, and atmospheric layout are covered by Task 5.
- Reduced motion, privacy-safe mode, and fail-closed hidden mode are covered by Task 6.
- Sparse, no-bridge, and dominant-cluster edge cases are covered by Tasks 2 and 7.
- Engineering validation requirements are covered by Tasks 1, 2, 3, 4, 6, and 7.

No uncovered requirement from the UI spec remains inside this plan’s scope. Full CRUD management flows, the detail drawer, and provenance deep dive stay intentionally out of scope because the spec explicitly defers them.

### Placeholder Scan

- No `TODO`, `TBD`, or “implement later” placeholders remain.
- Each code-writing step includes concrete file paths and concrete code.
- Each verification step includes exact commands and explicit expected outcomes.

### Type Consistency

The plan uses one stable naming set throughout:

- `MemoryCenterQuery`
- `MemoryCatalogProviding`
- `MemoryConstellationDisplayMode`
- `MemoryConstellationBuilder`
- `MemoryConstellationStore`
- `MemoryConstellationSnapshot`

The cluster taxonomy is intentionally fixed to three visible major groups:

- `vocabulary`
- `style`
- `scenes`

`MemoryType.correction` is consistently mapped into the `vocabulary` visual cluster so the UI matches the approved filter set from the design spec.
