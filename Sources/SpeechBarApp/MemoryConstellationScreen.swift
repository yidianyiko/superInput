import Foundation
import SpeechBarDomain
import SwiftUI

struct MemoryConstellationScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var constellationStore: MemoryConstellationStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let palette: HomeWindowStore.HomeThemePalette
    let completedTranscript: PublishedTranscript?

    @State private var activationProgress: CGFloat = 0

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
                activationProgress: activationProgress,
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
        .onAppear {
            guard !reduceMotion else {
                activationProgress = 1
                return
            }

            activationProgress = 0

            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeOut(duration: 1.4)) {
                    activationProgress = 1
                }
            }
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
        return ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(constellationTheme.canvasBackground)

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .vocabulary).opacity(0.24 + ((1 - activationProgress) * 0.12)),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .style).opacity(0.18 + ((1 - activationProgress) * 0.10)),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 340
            )

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            constellationTheme.focusAccent.opacity(0.16),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 820, height: 320)
                .blur(radius: 32)
                .offset(x: 42, y: -24)
        }
    }
}
