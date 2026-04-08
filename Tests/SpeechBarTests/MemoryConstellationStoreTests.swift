import Foundation
import Testing
import MemoryDomain
@testable import SpeechBarApp

@Suite("MemoryConstellationStore")
struct MemoryConstellationStoreTests {
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
        #expect(store.snapshot.relationshipCards.first?.body.contains("Vocabulary") == true)
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
}

private struct InlineCatalogProvider: MemoryCatalogProviding {
    let memories: [MemoryItem]

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        memories
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
