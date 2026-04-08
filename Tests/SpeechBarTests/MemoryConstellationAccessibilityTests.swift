import Foundation
import MemoryDomain
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationAccessibility")
struct MemoryConstellationAccessibilityTests {
    @Test
    func fullModeSummaryNarratesMainThemesAndStrongestBridge() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let sharedEvent = UUID()

        let snapshot = builder.build(
            memories: [
                makeAccessibilityMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [sharedEvent]),
                makeAccessibilityMemory(type: .style, payload: "brevity=short", updatedAt: 95, eventIDs: [sharedEvent]),
                makeAccessibilityMemory(type: .scene, payload: "Mail Draft", updatedAt: 90, eventIDs: [UUID()])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .full
        )

        #expect(snapshot.accessibilitySummary.contains("Main themes include Vocabulary, Style, and Scenes."))
        #expect(snapshot.accessibilitySummary.contains("Strongest bridge connects Vocabulary and Style."))
    }

    @Test
    func privacySafeSummaryKeepsThemeNarrationWithoutRawTerms() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        let sharedEvent = UUID()

        let snapshot = builder.build(
            memories: [
                makeAccessibilityMemory(type: .vocabulary, payload: "Confidential Project Hera", updatedAt: 100, eventIDs: [sharedEvent]),
                makeAccessibilityMemory(type: .style, payload: "Use customer-first phrasing", updatedAt: 96, eventIDs: [sharedEvent]),
                makeAccessibilityMemory(type: .scene, payload: "Quarterly review note", updatedAt: 92, eventIDs: [UUID()])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .privacySafe
        )

        #expect(snapshot.accessibilitySummary.contains("Protected memory constellation."))
        #expect(snapshot.accessibilitySummary.contains("Main themes include Vocabulary, Style, and Scenes."))
        #expect(snapshot.accessibilitySummary.contains("Strongest protected bridge connects Vocabulary and Style."))
        #expect(snapshot.accessibilitySummary.localizedCaseInsensitiveContains("hera") == false)
        #expect(snapshot.accessibilitySummary.localizedCaseInsensitiveContains("customer-first") == false)
        #expect(snapshot.accessibilitySummary.localizedCaseInsensitiveContains("quarterly review") == false)
    }

    @Test
    func hiddenModeRemainsFailClosed() {
        let builder = MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })

        let snapshot = builder.build(
            memories: [
                makeAccessibilityMemory(type: .vocabulary, payload: "OpenAI", updatedAt: 100, eventIDs: [UUID()])
            ],
            filter: .all,
            focus: .overview,
            viewMode: .clusterMap,
            displayMode: .hidden
        )

        #expect(snapshot == .hidden)
        #expect(snapshot.accessibilitySummary == "Memory visibility is hidden. No constellation is shown.")
        #expect(snapshot.relationshipCards.isEmpty)
    }
}

private func makeAccessibilityMemory(
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
