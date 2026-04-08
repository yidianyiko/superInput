import SwiftUI

struct MemoryConstellationHeaderView: View {
    let snapshot: MemoryConstellationSnapshot
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let refreshPresentation: () -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memory Constellation")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(MemoryConstellationTheme.secondaryText.opacity(0.9))

                    Text(snapshot.title)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(MemoryConstellationTheme.primaryText)

                    Text(snapshot.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ForEach(headerTags, id: \.self) { tag in
                            MemoryConstellationTag(title: tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Visibility", selection: $memoryFeatureFlagStore.displayMode) {
                        ForEach(MemoryConstellationDisplayMode.allCases, id: \.self) { mode in
                            Text(MemoryConstellationTheme.displayModeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(MemoryConstellationTheme.focusGold)
                    .onChange(of: memoryFeatureFlagStore.displayMode) { _ in
                        refreshPresentation()
                    }

                    HStack(spacing: 8) {
                        statusPill(title: memoryFeatureFlagStore.captureEnabled ? "Capture On" : "Capture Off")
                        statusPill(title: memoryFeatureFlagStore.recallEnabled ? "Recall On" : "Recall Off")
                    }
                }
            }
        }
    }

    private var headerTags: [String] {
        snapshot.statusPills + [
            "\(snapshot.clusters.reduce(0) { $0 + $1.itemCount }) memories"
        ]
    }

    private func statusPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(MemoryConstellationTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(MemoryConstellationTheme.elevatedFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
