import Combine
import Foundation
import MemoryDomain
import SpeechBarDomain

@MainActor
final class MemoryConstellationStore: ObservableObject {
    @Published private(set) var snapshot: MemoryConstellationSnapshot = .hidden
    @Published private(set) var focus: MemoryConstellationFocus = .overview
    @Published private(set) var selectedMemory: MemoryItem? = nil
    @Published private(set) var selectedTimelineWindowID: String? = nil
    @Published private(set) var selectedFilter: MemoryConstellationClusterFilter = .all
    @Published private(set) var selectedViewMode: MemoryConstellationViewMode = .clusterMap
    @Published private(set) var capturePulseToken = 0

    private let catalog: (any MemoryCatalogProviding)?
    private let featureFlags: MemoryFeatureFlagStore
    private let builder: MemoryConstellationBuilder
    private var memories: [MemoryItem] = []
    private var lastPulsedTranscriptAt: Date?
    private var awaitingCaptureDiff = false
    private var recentCaptureCount: Int?
    private var recentlyAddedIdentityHashes: Set<String> = []

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

        let previousActiveIdentityHashes = Set(memories.lazy.filter { $0.status == .active }.map(\.identityHash))
        let nextActiveIdentityHashes = Set(liveMemories.lazy.filter { $0.status == .active }.map(\.identityHash))

        if awaitingCaptureDiff {
            let insertedIdentityHashes = nextActiveIdentityHashes.subtracting(previousActiveIdentityHashes)
            recentlyAddedIdentityHashes = insertedIdentityHashes
            recentCaptureCount = insertedIdentityHashes.isEmpty ? nil : insertedIdentityHashes.count
            awaitingCaptureDiff = false
        } else {
            recentlyAddedIdentityHashes.formIntersection(nextActiveIdentityHashes)
            if recentlyAddedIdentityHashes.isEmpty {
                recentCaptureCount = nil
            }
        }

        memories = liveMemories
        reconcileSelection()
        rebuildSnapshot()
    }

    func hoverCluster(_ cluster: MemoryConstellationClusterKind?) {
        if let cluster {
            focus = .cluster(cluster)
        } else {
            focus = .overview
        }
        selectedMemory = nil
        rebuildSnapshot()
    }

    func selectFilter(_ filter: MemoryConstellationClusterFilter) {
        selectedFilter = filter
        reconcileSelection()
        rebuildSnapshot()
    }

    func focusBridge(_ bridgeID: UUID?) {
        if let bridgeID {
            focus = .bridge(bridgeID)
        } else {
            focus = .overview
        }
        selectedMemory = nil
        rebuildSnapshot()
    }

    func focusStar(_ memoryID: UUID?) {
        if let memoryID, let memory = filteredActiveMemories().first(where: { $0.id == memoryID }) {
            focus = .star(memoryID)
            selectedMemory = memory
        } else {
            focus = .overview
            selectedMemory = nil
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

    func registerCompletedTranscriptPulse(_ transcript: PublishedTranscript) {
        guard lastPulsedTranscriptAt != transcript.createdAt else {
            return
        }

        lastPulsedTranscriptAt = transcript.createdAt
        awaitingCaptureDiff = true
        capturePulseToken &+= 1
    }

    func hideSelectedMemory() async {
        guard let manager = catalog as? any MemoryCatalogManaging,
              let selectedMemory else {
            return
        }

        do {
            try await manager.markHidden(identityHash: selectedMemory.identityHash, hiddenAt: Date())
            await reload()
        } catch {
            return
        }
    }

    func deleteSelectedMemory() async {
        guard let manager = catalog as? any MemoryCatalogManaging,
              let selectedMemory else {
            return
        }

        do {
            try await manager.markDeleted(identityHash: selectedMemory.identityHash, deletedAt: Date())
            await reload()
        } catch {
            return
        }
    }

    private func rebuildSnapshot() {
        snapshot = builder.build(
            memories: memories,
            filter: selectedFilter,
            focus: focus,
            viewMode: selectedViewMode,
            displayMode: featureFlags.displayMode,
            recentlyAddedIdentityHashes: recentlyAddedIdentityHashes,
            recentCaptureCount: recentCaptureCount
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

    private func filteredActiveMemories() -> [MemoryItem] {
        memories.filter { memory in
            memory.status == .active && includes(memory, in: selectedFilter)
        }
    }

    private func includes(_ memory: MemoryItem, in filter: MemoryConstellationClusterFilter) -> Bool {
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

    private func reconcileSelection() {
        guard case .star(let memoryID) = focus else {
            selectedMemory = nil
            return
        }

        guard let memory = filteredActiveMemories().first(where: { $0.id == memoryID }) else {
            focus = .overview
            selectedMemory = nil
            return
        }

        selectedMemory = memory
    }
}
