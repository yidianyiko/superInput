import Foundation
import MemoryDomain
import MemoryExtraction
import MemoryStorageSQLite

public actor MemoryCoordinator: MemoryRetriever, MemoryEventRecording {
    private let store: any MemoryStore
    private let extractor: any MemoryExtractor

    public init(store: any MemoryStore, extractor: any MemoryExtractor) {
        self.store = store
        self.extractor = extractor
    }

    public func record(event: InputEvent) async throws {
        try await ingest(event)
    }

    public func ingest(_ event: InputEvent) async throws {
        try await store.insert(event: event)
        let memories = try await extractor.extract(from: event)
        for memory in memories {
            try await store.upsert(memory: memory)
        }
    }

    public func recall(for request: RecallRequest) async throws -> RecallBundle {
        let ranked = try await store.listMemories(for: request).sorted(by: compareRank)
        let chosenByIdentity = chooseBestMemories(from: ranked)

        return RecallBundle(
            vocabularyHints: values(of: .vocabulary, from: chosenByIdentity, minimumConfidence: 0.60),
            correctionHints: values(of: .correction, from: chosenByIdentity, minimumConfidence: 0.60),
            styleHints: values(of: .style, from: chosenByIdentity, minimumConfidence: 0.60),
            sceneHints: values(of: .scene, from: chosenByIdentity, minimumConfidence: 0.60),
            diagnosticSummary: "memory_count=\(ranked.count)"
        )
    }

    private func compareRank(lhs: MemoryItem, rhs: MemoryItem) -> Bool {
        if lhs.scope.specificityRank != rhs.scope.specificityRank {
            return lhs.scope.specificityRank > rhs.scope.specificityRank
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }
        return (lhs.lastConfirmedAt ?? lhs.updatedAt) > (rhs.lastConfirmedAt ?? rhs.updatedAt)
    }

    private func chooseBestMemories(from ranked: [MemoryItem]) -> [MemoryItem] {
        var seenKeys = Set<String>()
        var chosen: [MemoryItem] = []

        for memory in ranked where memory.status == .active {
            let identity = "\(memory.type.rawValue)|\(memory.key)"
            if seenKeys.insert(identity).inserted {
                chosen.append(memory)
            }
        }

        return chosen
    }

    private func values(
        of type: MemoryType,
        from memories: [MemoryItem],
        minimumConfidence: Double
    ) -> [String] {
        memories
            .filter { $0.type == type && $0.confidence >= minimumConfidence }
            .compactMap { String(data: $0.valuePayload, encoding: .utf8) }
    }
}
