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
