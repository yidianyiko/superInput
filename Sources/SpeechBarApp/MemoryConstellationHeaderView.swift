import SwiftUI

struct MemoryConstellationHeaderView: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let snapshot: MemoryConstellationSnapshot
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let refreshPresentation: () -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 22) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("记忆星图")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(constellationTheme.secondaryText.opacity(0.9))

                    Text(snapshot.title)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(constellationTheme.primaryText)

                    Text(snapshot.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(constellationTheme.secondaryText)
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
                    Picker("显示模式", selection: $memoryFeatureFlagStore.displayMode) {
                        ForEach(MemoryConstellationDisplayMode.allCases, id: \.self) { mode in
                            Text(MemoryConstellationTheme.displayModeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(constellationTheme.focusAccent)
                    .onChange(of: memoryFeatureFlagStore.displayMode) { _ in
                        refreshPresentation()
                    }

                    HStack(spacing: 8) {
                        statusPill(title: memoryFeatureFlagStore.captureEnabled ? "采集开启" : "采集关闭")
                        statusPill(title: memoryFeatureFlagStore.recallEnabled ? "召回开启" : "召回关闭")
                    }
                }
            }
        }
    }

    private var headerTags: [String] {
        snapshot.statusPills + [
            "\(snapshot.clusters.reduce(0) { $0 + $1.itemCount }) 条记忆"
        ]
    }

    private func statusPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(constellationTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(constellationTheme.elevatedFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(constellationTheme.surfaceStroke, lineWidth: 1)
            )
    }
}
