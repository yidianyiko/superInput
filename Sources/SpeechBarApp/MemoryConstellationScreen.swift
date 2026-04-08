import SwiftUI

struct MemoryConstellationScreen: View {
    @ObservedObject var constellationStore: MemoryConstellationStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore

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
                hoverCluster: constellationStore.hoverCluster,
                focusBridge: constellationStore.focusBridge
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
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
        .padding(2)
        .environment(\.colorScheme, .dark)
        .task {
            await constellationStore.reload()
        }
        .onChange(of: memoryFeatureFlagStore.displayMode) { _ in
            constellationStore.refreshPresentation()
        }
    }

    private var screenBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(MemoryConstellationTheme.canvasBackground)

            RadialGradient(
                colors: [
                    MemoryConstellationTheme.clusterColor(for: .vocabulary).opacity(0.16),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 320
            )

            RadialGradient(
                colors: [
                    MemoryConstellationTheme.clusterColor(for: .style).opacity(0.14),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 300
            )
        }
    }
}
