import Foundation
import Testing
import MemoryDomain
@testable import MemoryCore

@Suite("MemoryCatalog")
struct MemoryCatalogTests {
    @Test
    func queryDefaultsToActiveAllTypesAndNoLimit() {
        let query = MemoryCenterQuery()

        #expect(query.statuses == [.active])
        #expect(query.types == Set(MemoryType.allCases))
        #expect(query.limit == nil)
    }

    @Test
    func coordinatorForwardsCatalogQueryToStore() async throws {
        let query = MemoryCenterQuery(
            statuses: [.active],
            types: [.vocabulary],
            limit: 8
        )
        let store = CatalogStoreStub(
            memories: [
                makeMemory(type: .vocabulary, status: .active, value: "active vocabulary"),
                makeMemory(type: .scene, status: .deleted, value: "deleted scene")
            ]
        )
        let core = MemoryCoordinator(store: store, extractor: StaticMemoryExtractor(memories: []))

        let memories = try await core.listMemories(matching: query)

        #expect(await store.capturedQueries() == [query])
        #expect(memories.count == 1)
        #expect(memories.first?.type == .vocabulary)
        #expect(memories.first.flatMap { String(data: $0.valuePayload, encoding: .utf8) } == "active vocabulary")
    }
}

private actor CatalogStoreStub: MemoryStore {
    private(set) var receivedQueries: [MemoryCenterQuery] = []
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
        receivedQueries.append(query)
        return memories.filter { query.statuses.contains($0.status) && query.types.contains($0.type) }
    }

    func markHidden(identityHash: String, hiddenAt: Date) async throws {}

    func markDeleted(identityHash: String, deletedAt: Date) async throws {}

    func capturedQueries() -> [MemoryCenterQuery] {
        receivedQueries
    }
}

private struct StaticMemoryExtractor: MemoryExtractor {
    let memories: [MemoryItem]

    func extract(from event: InputEvent) async throws -> [MemoryItem] {
        memories
    }
}

private func makeMemory(type: MemoryType, status: MemoryStatus, value: String) -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: type,
        key: "key-\(type.rawValue)-\(status.rawValue)",
        valuePayload: Data(value.utf8),
        valueFingerprint: value,
        identityHash: "\(type.rawValue)-\(status.rawValue)-\(value)",
        scope: .global,
        confidence: 0.9,
        status: status,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        lastConfirmedAt: Date(timeIntervalSince1970: 0),
        sourceEventIDs: []
    )
}
