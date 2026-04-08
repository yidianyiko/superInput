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
        .padding(2)
        .task {
            await constellationStore.reload()
        }
        .onChange(of: memoryFeatureFlagStore.displayMode) { _ in
            constellationStore.refreshPresentation()
        }
    }
}
