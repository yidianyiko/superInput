import Foundation
import Testing
import MemoryDomain
import SpeechBarDomain
@testable import SpeechBarApp

@Suite("MemoryConstellationStore")
struct MemoryConstellationStoreTests {
    @Test
    @MainActor
    func reloadFallsBackToDemoConstellationWhenNoRealMemoriesExist() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.demo-empty.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: []),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()

        #expect(store.snapshot.clusters.map(\.kind) == [.vocabulary, .style, .scenes])
        #expect(store.snapshot.statusPills.contains("30 条记忆"))
        #expect(store.snapshot.clusters.reduce(0) { $0 + $1.itemCount } == 30)
    }

    @Test
    @MainActor
    func reloadAugmentsSparseRealMemoriesWithDemoConstellation() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.demo-sparse.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()

        #expect(store.snapshot.clusters.contains(where: { $0.kind == .scenes }))
        #expect(store.snapshot.statusPills.contains("30 条记忆"))
        #expect(store.snapshot.clusters.reduce(0) { $0 + $1.itemCount } == 30)
        #expect(store.snapshot.clusters.contains(where: { cluster in
            cluster.kind == .vocabulary && cluster.stars.contains(where: { $0.label == "OpenAI" })
        }))
    }

    @Test
    @MainActor
    func reloadStopsUsingDemoMemoriesOnceRealMemoriesReachFiveItems() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationStore.demo-live.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let store = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: fiveVocabularyMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )

        await store.reload()

        #expect(store.snapshot.clusters.map(\.kind) == [.vocabulary])
        #expect(store.snapshot.statusPills.contains("5 条记忆"))
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

private func fiveVocabularyMemories() -> [MemoryItem] {
    (0..<5).map { index in
        MemoryItem(
            id: UUID(),
            type: .vocabulary,
            key: "vocabulary:demo-\(index)",
            valuePayload: Data("Demo \(index)".utf8),
            valueFingerprint: "Demo \(index)",
            identityHash: "vocabulary|demo-\(index)",
            scope: .app("com.apple.mail"),
            confidence: 0.90 - (Double(index) * 0.05),
            status: .active,
            createdAt: Date(timeIntervalSince1970: 100 - Double(index)),
            updatedAt: Date(timeIntervalSince1970: 100 - Double(index)),
            lastConfirmedAt: Date(timeIntervalSince1970: 100 - Double(index)),
            sourceEventIDs: [UUID()]
        )
    }
}
