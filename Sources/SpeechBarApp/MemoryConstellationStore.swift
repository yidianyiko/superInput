import Combine
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
    private let demoPresentationMemoryCount = 30
    private let minimumLiveMemoryCountForRealOnlyPresentation = 5

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
        let liveMemories: [MemoryItem]
        do {
            liveMemories = try await catalog?.listMemories(matching: MemoryCenterQuery(limit: 200)) ?? []
        } catch {
            liveMemories = []
        }
        memories = presentationMemories(from: liveMemories)
        rebuildSnapshot()
    }

    func hoverCluster(_ cluster: MemoryConstellationClusterKind?) {
        if let cluster {
            focus = .cluster(cluster)
        } else {
            focus = .overview
        }
        rebuildSnapshot()
    }

    func selectFilter(_ filter: MemoryConstellationClusterFilter) {
        selectedFilter = filter
        rebuildSnapshot()
    }

    func focusBridge(_ bridgeID: UUID?) {
        if let bridgeID {
            focus = .bridge(bridgeID)
        } else {
            focus = .overview
        }
        rebuildSnapshot()
    }

    func selectViewMode(_ viewMode: MemoryConstellationViewMode) {
        selectedViewMode = viewMode
        if viewMode != .timelineReplay {
            selectedTimelineWindowID = nil
        }
        rebuildSnapshot()
    }

    func selectTimelineWindow(_ windowID: String?) {
        selectedTimelineWindowID = windowID
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

    private func presentationMemories(from liveMemories: [MemoryItem]) -> [MemoryItem] {
        guard liveMemories.count < minimumLiveMemoryCountForRealOnlyPresentation else {
            return liveMemories
        }

        let now = builder.now()
        guard !liveMemories.isEmpty else {
            return Array(MemoryConstellationFixtures.defaultMemories(now: now).prefix(demoPresentationMemoryCount))
        }

        let neededSupplementCount = max(demoPresentationMemoryCount - liveMemories.count, 0)
        let representedKinds = Set(liveMemories.map(clusterKind(for:)))
        let seenIdentityHashes = Set(liveMemories.map(\.identityHash))

        let demoCandidates = uniqueDemoCandidates(now: now, excluding: seenIdentityHashes)
        let supplementalDemoMemories = prioritizedDemoCandidates(
            from: demoCandidates,
            representedKinds: representedKinds
        )
        .prefix(neededSupplementCount)
        .map { softenedDemoMemory($0, now: now) }

        return liveMemories + supplementalDemoMemories
    }

    private func uniqueDemoCandidates(now: Date, excluding identityHashes: Set<String>) -> [MemoryItem] {
        var seen = identityHashes
        let candidates = MemoryConstellationFixtures.defaultMemories(now: now)
            + MemoryConstellationFixtures.dominantMemories(now: now)

        return candidates.filter { seen.insert($0.identityHash).inserted }
    }

    private func prioritizedDemoCandidates(
        from candidates: [MemoryItem],
        representedKinds: Set<MemoryConstellationClusterKind>
    ) -> [MemoryItem] {
        let missingKinds = MemoryConstellationClusterKind.allCases.filter { !representedKinds.contains($0) }
        let preferred = candidates.filter { missingKinds.contains(clusterKind(for: $0)) }
        let remaining = candidates.filter { !missingKinds.contains(clusterKind(for: $0)) }
        return preferred + remaining
    }

    private func softenedDemoMemory(_ memory: MemoryItem, now: Date) -> MemoryItem {
        let softenedUpdatedAt = min(memory.updatedAt, now.addingTimeInterval(-48 * 60 * 60))
        let softenedCreatedAt = min(memory.createdAt, softenedUpdatedAt.addingTimeInterval(-10))

        return MemoryItem(
            id: memory.id,
            type: memory.type,
            key: memory.key,
            valuePayload: memory.valuePayload,
            valueFingerprint: memory.valueFingerprint,
            identityHash: memory.identityHash,
            scope: memory.scope,
            confidence: min(memory.confidence, 0.58),
            status: memory.status,
            createdAt: softenedCreatedAt,
            updatedAt: softenedUpdatedAt,
            lastConfirmedAt: softenedUpdatedAt,
            sourceEventIDs: memory.sourceEventIDs
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
}
