import Foundation
import SpeechBarDomain
import SwiftUI

struct MemoryConstellationScreen: View {
    @ObservedObject var constellationStore: MemoryConstellationStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let palette: HomeWindowStore.HomeThemePalette
    let completedTranscript: PublishedTranscript?

    private var constellationTheme: MemoryConstellationVisualTheme {
        MemoryConstellationVisualTheme(palette: palette)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MemoryConstellationHeaderView(
                snapshot: constellationStore.snapshot,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            ) {
                constellationStore.refreshPresentation()
            }

            MemoryConstellationToolbarView(
                selectedFilter: constellationStore.selectedFilter,
                selectedViewMode: constellationStore.selectedViewMode,
                selectFilter: constellationStore.selectFilter,
                selectViewMode: constellationStore.selectViewMode
            )

            MemoryConstellationCanvasView(
                snapshot: constellationStore.snapshot,
                focus: constellationStore.focus,
                selectedViewMode: constellationStore.selectedViewMode,
                capturePulseToken: constellationStore.capturePulseToken,
                hoverCluster: constellationStore.hoverCluster,
                focusBridge: constellationStore.focusBridge,
                focusStar: constellationStore.focusStar
            )

            MemoryConstellationDetailPanelView(
                memory: constellationStore.selectedMemory,
                displayMode: memoryFeatureFlagStore.displayMode,
                hasVisibleMemories: constellationStore.snapshot.clusters.isEmpty == false,
                hideSelectedMemory: {
                    Task {
                        await constellationStore.hideSelectedMemory()
                    }
                },
                deleteSelectedMemory: {
                    Task {
                        await constellationStore.deleteSelectedMemory()
                    }
                }
            )

            MemoryConstellationRelationshipTrayView(
                cards: constellationStore.snapshot.relationshipCards,
                focusBridge: constellationStore.focusBridge
            )

            MemoryTimelineRibbonView(
                timeline: constellationStore.snapshot.timeline,
                selectedViewMode: constellationStore.selectedViewMode,
                selectedTimelineWindowID: constellationStore.selectedTimelineWindowID,
                selectViewMode: constellationStore.selectViewMode,
                selectTimelineWindow: constellationStore.selectTimelineWindow
            )

            MemoryProfileSettingsSection(
                userProfileStore: userProfileStore,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            )
        }
        .padding(24)
        .background(screenBackground)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(constellationTheme.screenBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
        .padding(2)
        .environment(\.memoryConstellationTheme, constellationTheme)
        .environment(\.colorScheme, palette.preferredColorScheme)
        .task {
            await constellationStore.reload()
        }
        .onChange(of: memoryFeatureFlagStore.displayMode) { _ in
            constellationStore.refreshPresentation()
        }
        .onChange(of: completedTranscript) { transcript in
            guard let transcript else { return }
            constellationStore.registerCompletedTranscriptPulse(transcript)
            Task {
                try? await Task.sleep(for: .milliseconds(320))
                await constellationStore.reload()
            }
        }
    }

    private var screenBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(constellationTheme.canvasBackground)

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .vocabulary).opacity(0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 320
            )

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .style).opacity(0.12),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 300
            )
        }
    }
}
