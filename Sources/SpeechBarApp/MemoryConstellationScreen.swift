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

    @State private var pointerVector: CGPoint = .zero
    @State private var activationProgress: CGFloat = 0
    @State private var hasPlayedActivation = false

    private var constellationTheme: MemoryConstellationVisualTheme {
        MemoryConstellationVisualTheme(palette: palette)
    }

    var body: some View {
        GeometryReader { proxy in
            let screenVector = reduceMotion ? .zero : pointerVector

            VStack(alignment: .leading, spacing: 20) {
                MemoryConstellationHeaderView(
                    snapshot: constellationStore.snapshot,
                    memoryFeatureFlagStore: memoryFeatureFlagStore
                ) {
                    constellationStore.refreshPresentation()
                }
                .offset(screenLayerOffset(maxX: 7, maxY: 5))

                MemoryConstellationToolbarView(
                    selectedFilter: constellationStore.selectedFilter,
                    selectedViewMode: constellationStore.selectedViewMode,
                    selectFilter: constellationStore.selectFilter,
                    selectViewMode: constellationStore.selectViewMode
                )
                .offset(screenLayerOffset(maxX: 10, maxY: 6))

                MemoryConstellationCanvasView(
                    snapshot: constellationStore.snapshot,
                    focus: constellationStore.focus,
                    selectedViewMode: constellationStore.selectedViewMode,
                    capturePulseToken: constellationStore.capturePulseToken,
                    pointerVector: screenVector,
                    activationProgress: activationProgress,
                    hoverCluster: constellationStore.hoverCluster,
                    focusBridge: constellationStore.focusBridge,
                    focusStar: constellationStore.focusStar
                )
                .offset(screenLayerOffset(maxX: 14, maxY: 10))

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
                .offset(screenLayerOffset(maxX: 9, maxY: 6))

                MemoryConstellationRelationshipTrayView(
                    cards: constellationStore.snapshot.relationshipCards,
                    focusBridge: constellationStore.focusBridge
                )
                .offset(screenLayerOffset(maxX: 8, maxY: 6))

                MemoryTimelineRibbonView(
                    timeline: constellationStore.snapshot.timeline,
                    selectedViewMode: constellationStore.selectedViewMode,
                    selectedTimelineWindowID: constellationStore.selectedTimelineWindowID,
                    selectViewMode: constellationStore.selectViewMode,
                    selectTimelineWindow: constellationStore.selectTimelineWindow
                )
                .offset(screenLayerOffset(maxX: 8, maxY: 6))

                MemoryProfileSettingsSection(
                    userProfileStore: userProfileStore,
                    memoryFeatureFlagStore: memoryFeatureFlagStore
                )
                .offset(screenLayerOffset(maxX: 4, maxY: 4))
            }
            .padding(24)
            .background(screenBackground(size: proxy.size))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(constellationTheme.screenBorder, lineWidth: 1)
            )
            .rotation3DEffect(.degrees(Double(screenVector.y) * 1.8), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(Double(screenVector.x) * -2.3), axis: (x: 0, y: 1, z: 0))
            .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
            .padding(2)
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.26, dampingFraction: 0.82), value: screenVector)
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard !reduceMotion else { return }
                switch phase {
                case .active(let location):
                    pointerVector = MemoryConstellationMotion.normalizedPointer(location: location, in: proxy.size)
                case .ended:
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        pointerVector = .zero
                    }
                }
            }
        }
        .environment(\.memoryConstellationTheme, constellationTheme)
        .environment(\.colorScheme, palette.preferredColorScheme)
        .task {
            await constellationStore.reload()
        }
        .onAppear {
            guard !hasPlayedActivation else { return }
            hasPlayedActivation = true

            guard !reduceMotion else {
                activationProgress = 1
                return
            }

            withAnimation(.easeOut(duration: 1.15)) {
                activationProgress = 1
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

    private func screenBackground(size: CGSize) -> some View {
        let leadingHaloCenter = UnitPoint(
            x: min(max(0.24 + (pointerVector.x * 0.06), 0.08), 0.92),
            y: min(max(0.20 + (pointerVector.y * 0.05), 0.08), 0.92)
        )
        let trailingHaloCenter = UnitPoint(
            x: min(max(0.82 - (pointerVector.x * 0.08), 0.08), 0.92),
            y: min(max(0.78 - (pointerVector.y * 0.06), 0.08), 0.92)
        )
        let sheenOffset = MemoryConstellationMotion.parallaxOffset(
            pointerVector: pointerVector,
            maxX: size.width * 0.04,
            maxY: size.height * 0.03
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(constellationTheme.canvasBackground)

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .vocabulary).opacity(0.24 + ((1 - activationProgress) * 0.12)),
                    Color.clear
                ],
                center: leadingHaloCenter,
                startRadius: 30,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    constellationTheme.clusterColor(for: .style).opacity(0.18 + ((1 - activationProgress) * 0.10)),
                    Color.clear
                ],
                center: trailingHaloCenter,
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
                .frame(width: size.width * 0.78, height: size.height * 0.52)
                .blur(radius: 32)
                .offset(sheenOffset)
        }
    }

    private func screenLayerOffset(maxX: CGFloat, maxY: CGFloat) -> CGSize {
        guard !reduceMotion else {
            return .zero
        }
        return MemoryConstellationMotion.parallaxOffset(
            pointerVector: pointerVector,
            maxX: maxX,
            maxY: maxY
        )
    }
}
