import SwiftUI

struct MemoryTimelineRibbonView: View {
    let timeline: MemoryConstellationTimeline
    let selectedViewMode: MemoryConstellationViewMode
    let selectedTimelineWindowID: String?
    let selectViewMode: (MemoryConstellationViewMode) -> Void
    let selectTimelineWindow: (String?) -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeline Replay")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(MemoryConstellationTheme.secondaryText)

                        Text("Replay how clusters thicken and how bridges emerge over time.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MemoryConstellationTheme.secondaryText)
                    }

                    Spacer()

                    MemoryConstellationChip(
                        title: selectedViewMode == .timelineReplay ? "Replay Active" : "Enter Replay",
                        isSelected: selectedViewMode == .timelineReplay
                    ) {
                        selectViewMode(
                            selectedViewMode == .timelineReplay
                                ? .clusterMap
                                : .timelineReplay
                        )
                    }
                }

                if timeline.windows.isEmpty {
                    Text("The ribbon is waiting for enough memory history to show a meaningful formation replay.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                } else {
                    HStack(spacing: 10) {
                        ForEach(timeline.windows) { window in
                            Button {
                                if selectedViewMode != .timelineReplay {
                                    selectViewMode(.timelineReplay)
                                }
                                selectTimelineWindow(window.id == selectedTimelineWindowID ? nil : window.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(window.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Text("\(window.memoryCount) memories")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(MemoryConstellationTheme.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(backgroundFill(for: window))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(borderColor(for: window), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func backgroundFill(for window: MemoryConstellationTimelineWindow) -> Color {
        window.id == selectedTimelineWindowID && selectedViewMode == .timelineReplay
            ? MemoryConstellationTheme.accentGold.opacity(0.22)
            : Color.white.opacity(0.05)
    }

    private func borderColor(for window: MemoryConstellationTimelineWindow) -> Color {
        window.id == selectedTimelineWindowID && selectedViewMode == .timelineReplay
            ? MemoryConstellationTheme.focusGold.opacity(0.70)
            : Color.white.opacity(0.08)
    }
}
