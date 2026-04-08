import Foundation
import MemoryDomain

actor MemoryDemoSeeder {
    private let store: any MemoryStore
    private let referenceDate: Date

    init(
        store: any MemoryStore,
        referenceDate: Date = Date(timeIntervalSince1970: 1_775_404_800)
    ) {
        self.store = store
        self.referenceDate = referenceDate
    }

    func seedMissingDemoMemories() async throws -> Int {
        let existing = try await store.listMemories(
            matching: MemoryCenterQuery(
                statuses: Set(MemoryStatus.allCases),
                types: Set(MemoryType.allCases),
                limit: 512
            )
        )
        let existingIdentityHashes = Set(existing.map(\.identityHash))
        let missingDemoMemories = MemoryConstellationFixtures.defaultMemories(now: referenceDate)
            .filter { !existingIdentityHashes.contains($0.identityHash) }

        for memory in missingDemoMemories {
            try await store.upsert(memory: memory)
        }

        return missingDemoMemories.count
    }
}
