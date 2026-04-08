import AppKit
import Foundation
import MemoryDomain
import SwiftUI
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationScreenSmoke")
struct MemoryConstellationScreenSmokeTests {
    @Test
    func clusterInteractionStateKeepsClickedFocusAfterHoverExit() {
        var interaction = MemoryConstellationClusterInteractionState()

        #expect(interaction.hoverChanged(to: .vocabulary) == .vocabulary)
        #expect(interaction.clusterClicked(.vocabulary) == .vocabulary)
        #expect(interaction.hoverChanged(to: nil) == .vocabulary)
    }

    @Test
    @MainActor
    func screenRendersInsideHostingView() async throws {
        let defaults = UserDefaults(suiteName: "MemoryConstellationScreenSmoke.screen.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let constellationStore = MemoryConstellationStore(
            catalog: InlineCatalogProvider(memories: sampleMemories()),
            featureFlags: featureFlags,
            builder: MemoryConstellationBuilder(now: { Date(timeIntervalSince1970: 100) })
        )
        let userProfileStore = UserProfileStore(defaults: defaults)

        await constellationStore.reload()

        let rootView = MemoryConstellationScreen(
            constellationStore: constellationStore,
            userProfileStore: userProfileStore,
            memoryFeatureFlagStore: featureFlags,
            completedTranscript: nil
        )
        let hostingView = NSHostingView(rootView: rootView.frame(width: 980, height: 860))

        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.fittingSize.width > 0)
        #expect(hostingView.fittingSize.height > 0)
        #expect(constellationStore.snapshot.title == "我的记忆宇宙")
        #expect(constellationStore.snapshot.clusters.isEmpty == false)
    }

    @Test
    @MainActor
    func profileSectionRendersAsSecondaryControls() {
        let defaults = UserDefaults(suiteName: "MemoryConstellationScreenSmoke.profile.\(UUID().uuidString)")!
        let featureFlags = MemoryFeatureFlagStore(defaults: defaults)
        let userProfileStore = UserProfileStore(defaults: defaults)
        let section = MemoryProfileSettingsSection(
            userProfileStore: userProfileStore,
            memoryFeatureFlagStore: featureFlags
        )
        let hostingView = NSHostingView(rootView: section.frame(width: 920))

        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.fittingSize.width > 0)
        #expect(hostingView.fittingSize.height > 0)
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
            confidence: 0.92,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 90),
            updatedAt: Date(timeIntervalSince1970: 90),
            lastConfirmedAt: Date(timeIntervalSince1970: 90),
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
            confidence: 0.83,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 88),
            updatedAt: Date(timeIntervalSince1970: 88),
            lastConfirmedAt: Date(timeIntervalSince1970: 88),
            sourceEventIDs: [shared]
        ),
        MemoryItem(
            id: UUID(),
            type: .scene,
            key: "scene:mail_draft",
            valuePayload: Data("Mail Draft".utf8),
            valueFingerprint: "Mail Draft",
            identityHash: "scene|mail_draft",
            scope: .app("com.apple.mail"),
            confidence: 0.79,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 82),
            updatedAt: Date(timeIntervalSince1970: 82),
            lastConfirmedAt: Date(timeIntervalSince1970: 82),
            sourceEventIDs: [shared]
        )
    ]
}
