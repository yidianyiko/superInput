import Foundation
import Testing
import MemoryDomain
import SpeechBarDomain
@testable import SpeechBarApp

@Suite("MemoryConstellationStore")
struct MemoryConstellationStoreTests {
    @Test
    @MainActor
    func reloadLeavesTheConstellationEmptyWhenNoRealMemoriesExist() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.empty.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: []),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()

        #expect(store.snapshot.clusters.isEmpty)
        #expect(store.snapshot.statusPills.contains("0 条记忆"))
        #expect(store.focus == .overview)
    }

    @Test
    @MainActor
    func reloadKeepsSparseRealMemoriesWithoutDemoSupplement() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.sparse.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()

        #expect(store.snapshot.clusters.map(\.kind) == [.vocabulary, .style])
        #expect(store.snapshot.statusPills.contains("2 条记忆"))
        #expect(store.snapshot.clusters.reduce(0) { $0 + $1.itemCount } == 2)
        #expect(store.snapshot.clusters.contains(where: { cluster in
            cluster.kind == .vocabulary && cluster.stars.contains(where: { $0.label == "OpenAI" })
        }))
    }

    @Test
    @MainActor
    func focusStarPublishesTheSelectedRealMemory() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.star-focus.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let memories = sampleMemories()
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: memories),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        let selectedID = try #require(memories.first?.id)
        store.focusStar(selectedID)

        #expect(store.focus == .star(selectedID))
        #expect(store.selectedMemory?.id == selectedID)
        #expect(store.selectedMemory?.valueFingerprint == "OpenAI")
    }

    @Test
    @MainActor
    func selectingAFilterClearsAStarThatIsNoLongerVisible() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.star-filter.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let memories = sampleMemories()
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: memories),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        let selectedID = try #require(memories.first?.id)
        store.focusStar(selectedID)
        store.selectFilter(.style)

        #expect(store.focus == .overview)
        #expect(store.selectedMemory == nil)
    }

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
        store.hoverCluster(nil)

        #expect(store.focus == .overview)
        #expect(store.snapshot.relationshipCards.first?.body.contains("词汇") == true)
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
        store.selectViewMode(.clusterMap)

        #expect(store.selectedViewMode == .clusterMap)
        #expect(store.selectedTimelineWindowID == nil)
    }

    @Test
    @MainActor
    func focusBridgeResetsToOverviewWhenCleared() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.bridge.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        let bridgeID = try #require(store.snapshot.highlightedBridges.first?.id)
        store.focusBridge(bridgeID)
        store.focusBridge(nil)

        #expect(store.focus == .overview)
    }

    @Test
    @MainActor
    func completedTranscriptPulseOnlyAdvancesForNewCompletions() {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.pulse.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )
        let first = PublishedTranscript(text: "First", createdAt: Date(timeIntervalSince1970: 100))
        let second = PublishedTranscript(text: "Second", createdAt: Date(timeIntervalSince1970: 101))

        #expect(store.capturePulseToken == 0)

        store.registerCompletedTranscriptPulse(first)
        #expect(store.capturePulseToken == 1)

        store.registerCompletedTranscriptPulse(first)
        #expect(store.capturePulseToken == 1)

        store.registerCompletedTranscriptPulse(second)
        #expect(store.capturePulseToken == 2)
    }

    @Test
    @MainActor
    func reloadAfterTranscriptPulseSurfacesRecentlyAddedMemorySignals() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.recent.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let initialMemories = sampleMemories()
        let addedMemory = MemoryItem(
            id: UUID(),
            type: .scene,
            key: "scene:investor-sync",
            valuePayload: Data("Investor Sync".utf8),
            valueFingerprint: "Investor Sync",
            identityHash: "scene|investor-sync",
            scope: .app("com.apple.mail"),
            confidence: 0.78,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 101),
            updatedAt: Date(timeIntervalSince1970: 101),
            lastConfirmedAt: Date(timeIntervalSince1970: 101),
            sourceEventIDs: [UUID()]
        )
        let catalog = MutableMemoryCatalog(memories: initialMemories)
        let store = MemoryConstellationStore(
            catalog: catalog,
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 120) })
        )

        await store.reload()
        store.registerCompletedTranscriptPulse(
            PublishedTranscript(text: "Hello", createdAt: Date(timeIntervalSince1970: 105))
        )
        await catalog.replaceMemories(initialMemories + [addedMemory])

        await store.reload()

        #expect(store.snapshot.statusPills.contains("本次新增 1 条"))
        let scenesCluster = try #require(store.snapshot.clusters.first(where: { $0.kind == .scenes }))
        #expect(scenesCluster.stars.contains(where: { $0.label == "Investor Sync" && $0.isRecentlyAdded }))
    }

    @Test
    @MainActor
    func hideSelectedMemoryMarksItHiddenAndClearsSelection() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.hide.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let memories = sampleMemories()
        let catalog = MutableManagingMemoryCatalog(memories: memories)
        let store = MemoryConstellationStore(
            catalog: catalog,
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        let selectedID = try #require(memories.first?.id)
        store.focusStar(selectedID)

        await store.hideSelectedMemory()

        #expect(await catalog.hiddenIdentityHashes() == ["vocabulary|openai"])
        #expect(store.selectedMemory == nil)
        #expect(store.snapshot.clusters.reduce(0) { $0 + $1.itemCount } == 1)
    }

    @Test
    @MainActor
    func deleteSelectedMemoryMarksItDeletedAndClearsSelection() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.delete.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let memories = sampleMemories()
        let catalog = MutableManagingMemoryCatalog(memories: memories)
        let store = MemoryConstellationStore(
            catalog: catalog,
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()
        let selectedID = try #require(memories.last?.id)
        store.focusStar(selectedID)

        await store.deleteSelectedMemory()

        #expect(await catalog.deletedIdentityHashes() == ["style|brevity"])
        #expect(store.selectedMemory == nil)
        #expect(store.snapshot.clusters.reduce(0) { $0 + $1.itemCount } == 1)
    }
}

private struct InlineCatalogProvider: MemoryCatalogProviding {
    let memories: [MemoryItem]

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        memories
    }
}

private actor MutableMemoryCatalog: MemoryCatalogProviding {
    private var memories: [MemoryItem]

    init(memories: [MemoryItem]) {
        self.memories = memories
    }

    func replaceMemories(_ memories: [MemoryItem]) {
        self.memories = memories
    }

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        memories.filter { memory in
            query.statuses.contains(memory.status) && query.types.contains(memory.type)
        }
    }
}

private actor MutableManagingMemoryCatalog: MemoryCatalogProviding, MemoryCatalogManaging {
    private var memories: [MemoryItem]
    private var hidden: [String] = []
    private var deleted: [String] = []

    init(memories: [MemoryItem]) {
        self.memories = memories
    }

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        memories.filter { memory in
            query.statuses.contains(memory.status) && query.types.contains(memory.type)
        }
    }

    func markHidden(identityHash: String, hiddenAt: Date) async throws {
        hidden.append(identityHash)
        memories = memories.map { memory in
            guard memory.identityHash == identityHash else {
                return memory
            }
            return MemoryItem(
                id: memory.id,
                type: memory.type,
                key: memory.key,
                valuePayload: memory.valuePayload,
                valueFingerprint: memory.valueFingerprint,
                identityHash: memory.identityHash,
                scope: memory.scope,
                confidence: memory.confidence,
                status: .hidden,
                createdAt: memory.createdAt,
                updatedAt: hiddenAt,
                lastConfirmedAt: memory.lastConfirmedAt,
                sourceEventIDs: memory.sourceEventIDs
            )
        }
    }

    func markDeleted(identityHash: String, deletedAt: Date) async throws {
        deleted.append(identityHash)
        memories = memories.map { memory in
            guard memory.identityHash == identityHash else {
                return memory
            }
            return MemoryItem(
                id: memory.id,
                type: memory.type,
                key: memory.key,
                valuePayload: memory.valuePayload,
                valueFingerprint: memory.valueFingerprint,
                identityHash: memory.identityHash,
                scope: memory.scope,
                confidence: memory.confidence,
                status: .deleted,
                createdAt: memory.createdAt,
                updatedAt: deletedAt,
                lastConfirmedAt: memory.lastConfirmedAt,
                sourceEventIDs: memory.sourceEventIDs
            )
        }
    }

    func hiddenIdentityHashes() -> [String] {
        hidden
    }

    func deletedIdentityHashes() -> [String] {
        deleted
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
