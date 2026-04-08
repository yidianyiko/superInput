import Foundation
import Testing
import MemoryDomain
@testable import SpeechBarApp

@Suite("MemoryDemoSeeder")
struct MemoryDemoSeederTests {
    @Test
    func seedMissingDemoMemoriesPopulatesEmptyStoreWithThirtyRows() async throws {
        let store = InMemorySeedStore()
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let seeder = MemoryDemoSeeder(store: store, referenceDate: referenceDate)

        let inserted = try await seeder.seedMissingDemoMemories()
        let stored = try await store.listMemories(
            matching: MemoryCenterQuery(
                statuses: Set(MemoryStatus.allCases),
                types: Set(MemoryType.allCases)
            )
        )

        #expect(inserted == 30)
        #expect(stored.count == 30)
        #expect(Set(stored.map(\.identityHash)).count == 30)
    }

    @Test
    func seedMissingDemoMemoriesSkipsExistingDemoRowsOnRepeatRuns() async throws {
        let store = InMemorySeedStore()
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let seeder = MemoryDemoSeeder(store: store, referenceDate: referenceDate)

        let firstInsertCount = try await seeder.seedMissingDemoMemories()
        let secondInsertCount = try await seeder.seedMissingDemoMemories()
        let stored = try await store.listMemories(
            matching: MemoryCenterQuery(
                statuses: Set(MemoryStatus.allCases),
                types: Set(MemoryType.allCases)
            )
        )

        #expect(firstInsertCount == 30)
        #expect(secondInsertCount == 0)
        #expect(stored.count == 30)
    }

    @Test
    func seedMissingDemoMemoriesPreservesRealRowsAndOnlyAddsMissingDemoRows() async throws {
        let store = InMemorySeedStore()
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        let existingDemoMemory = MemoryConstellationFixtures.defaultMemories(now: referenceDate)[0]
        let seeder = MemoryDemoSeeder(store: store, referenceDate: referenceDate)

        try await store.upsert(memory: existingDemoMemory)
        try await store.upsert(memory: realMemory())

        let inserted = try await seeder.seedMissingDemoMemories()
        let stored = try await store.listMemories(
            matching: MemoryCenterQuery(
                statuses: Set(MemoryStatus.allCases),
                types: Set(MemoryType.allCases)
            )
        )

        let demoIdentityHashes = Set(MemoryConstellationFixtures.defaultMemories(now: referenceDate).map(\.identityHash))
        let storedDemoCount = stored.filter { demoIdentityHashes.contains($0.identityHash) }.count

        #expect(inserted == 29)
        #expect(stored.count == 31)
        #expect(storedDemoCount == 30)
        #expect(stored.contains(where: { $0.identityHash == "real|mail-followup" }))
    }
}

private actor InMemorySeedStore: MemoryStore {
    private var memories: [MemoryItem] = []

    func insert(event: InputEvent) async throws {}

    func upsert(memory: MemoryItem) async throws {
        memories.removeAll { $0.identityHash == memory.identityHash }
        memories.append(memory)
    }

    func listMemories(for request: RecallRequest) async throws -> [MemoryItem] {
        memories
    }

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        let filtered = memories.filter { memory in
            query.statuses.contains(memory.status) && query.types.contains(memory.type)
        }

        if let limit = query.limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func markDeleted(identityHash: String, deletedAt: Date) async throws {}
}

private func realMemory() -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: .scene,
        key: "scene:real-mail-followup",
        valuePayload: Data("真实跟进".utf8),
        valueFingerprint: "真实跟进",
        identityHash: "real|mail-followup",
        scope: .app("com.apple.mail"),
        confidence: 0.91,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 500),
        updatedAt: Date(timeIntervalSince1970: 500),
        lastConfirmedAt: Date(timeIntervalSince1970: 500),
        sourceEventIDs: []
    )
}
