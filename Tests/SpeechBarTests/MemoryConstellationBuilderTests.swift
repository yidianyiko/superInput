import Foundation
import Testing
import MemoryDomain
@testable import SpeechBarApp

@Suite("MemoryConstellationBuilder")
struct MemoryConstellationBuilderTests {
    @Test
    func correctionMemoriesJoinTheVocabularyCluster() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let sharedEvent = UUID()

        let snapshot = builder.build(
            memories: [
                makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [sharedEvent]),
                makeMemory(type: .correction, payload: "Coze Space", updatedAt: 100, eventIDs: [sharedEvent]),
                makeMemory(type: .style, payload: "brevity=short", updatedAt: 90, eventIDs: [sharedEvent]),
                makeMemory(type: .scene, payload: "AXTextArea", updatedAt: 80, eventIDs: [sharedEvent])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.clusters.map(\.kind) == [.vocabulary, .style, .scenes])
        #expect(snapshot.clusters.first(where: { $0.kind == .vocabulary })?.stars.count == 2)
    }

    @Test
    func privacySafeModeSuppressesRawTerms() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })

        let snapshot = builder.build(
            memories: [makeMemory(type: .vocabulary, payload: "Confidential Project Hera", updatedAt: 100, eventIDs: [UUID()])],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .privacySafe
        )

        #expect(snapshot.clusters[0].stars[0].label == "受保护记忆")
        #expect(snapshot.relationshipCards[0].body.contains("受保护"))
    }

    @Test
    func noStrongBridgeFallsBackToEmergingThemesCopy() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })

        let snapshot = builder.build(
            memories: [
                makeMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [UUID()]),
                makeMemory(type: .style, payload: "brevity=short", updatedAt: 20, eventIDs: [UUID()])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.highlightedBridges.isEmpty)
        #expect(snapshot.guidanceCards.contains { $0.title == "正在形成的主题" })
    }

    @Test
    func denseClustersExposeUpToTenVisibleStars() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let sharedEvent = UUID()

        let snapshot = builder.build(
            memories: (0..<12).map { index in
                makeMemory(
                    type: .vocabulary,
                    payload: "Dense \(index)",
                    updatedAt: 100 - Double(index),
                    eventIDs: [sharedEvent]
                )
            },
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.clusters.first(where: { $0.kind == .vocabulary })?.stars.count == 10)
    }
}

private func makeMemory(
    type: MemoryType,
    payload: String,
    updatedAt: TimeInterval,
    eventIDs: [UUID]
) -> MemoryItem {
    MemoryItem(
        id: UUID(),
        type: type,
        key: "\(type.rawValue):\(payload.lowercased())",
        valuePayload: Data(payload.utf8),
        valueFingerprint: payload,
        identityHash: "\(type.rawValue)|\(payload)|\(updatedAt)",
        scope: .app("com.apple.mail"),
        confidence: 0.80,
        status: .active,
        createdAt: Date(timeIntervalSince1970: updatedAt),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        lastConfirmedAt: Date(timeIntervalSince1970: updatedAt),
        sourceEventIDs: eventIDs
    )
}
