import SwiftUI

enum MemoryConstellationTheme {
    static let canvasBackground = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.08, blue: 0.15),
            Color(red: 0.03, green: 0.04, blue: 0.10),
            Color(red: 0.02, green: 0.02, blue: 0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceFill = Color.white.opacity(0.08)
    static let elevatedFill = Color.white.opacity(0.12)
    static let surfaceStroke = Color.white.opacity(0.14)
    static let primaryText = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let secondaryText = Color(red: 0.78, green: 0.80, blue: 0.86)
    static let accentGold = Color(red: 0.84, green: 0.69, blue: 0.46)
    static let focusGold = Color(red: 0.95, green: 0.83, blue: 0.57)

    static func clusterColor(for kind: MemoryConstellationClusterKind) -> Color {
        switch kind {
        case .vocabulary:
            return Color(red: 0.41, green: 0.62, blue: 0.95)
        case .style:
            return Color(red: 0.82, green: 0.48, blue: 0.65)
        case .scenes:
            return Color(red: 0.44, green: 0.72, blue: 0.61)
        }
    }

    static func clusterGlow(for kind: MemoryConstellationClusterKind, emphasis: Double) -> RadialGradient {
        let base = clusterColor(for: kind)
        let strength = max(0.28, min(0.74, emphasis))
        return RadialGradient(
            colors: [
                base.opacity(strength),
                base.opacity(strength * 0.38),
                Color.clear
            ],
            center: .center,
            startRadius: 10,
            endRadius: 150
        )
    }

    static func displayModeLabel(_ mode: MemoryConstellationDisplayMode) -> String {
        switch mode {
        case .full:
            return "完整显示"
        case .privacySafe:
            return "隐私保护"
        case .hidden:
            return "隐藏"
        }
    }
}

struct MemoryConstellationPanel<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(MemoryConstellationTheme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(MemoryConstellationTheme.surfaceStroke, lineWidth: 1)
            )
    }
}

struct MemoryConstellationTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(MemoryConstellationTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct MemoryConstellationChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black.opacity(0.80) : MemoryConstellationTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            MemoryConstellationTheme.focusGold,
                                            MemoryConstellationTheme.accentGold
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color.white.opacity(0.06))
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? MemoryConstellationTheme.focusGold.opacity(0.8) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
