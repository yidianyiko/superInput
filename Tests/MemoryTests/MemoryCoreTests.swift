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

private struct StaticMemoryExtractor: MemoryExtractor {
    let memories: [MemoryItem]

    func extract(from event: InputEvent) async throws -> [MemoryItem] {
        memories
    }
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
        scope: .field(
            appIdentifier: "com.apple.mail",
            windowTitle: "Reply",
            fieldRole: "AXTextArea",
            fieldLabel: "Message Body"
        ),
        confidence: 0.80,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        lastConfirmedAt: Date(timeIntervalSince1970: 1),
        sourceEventIDs: []
    )
}
