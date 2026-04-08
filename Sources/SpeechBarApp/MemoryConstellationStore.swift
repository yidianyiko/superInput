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
        do {
            memories = try await catalog?.listMemories(matching: MemoryCenterQuery(limit: 200)) ?? []
        } catch {
            memories = []
        }
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
}
