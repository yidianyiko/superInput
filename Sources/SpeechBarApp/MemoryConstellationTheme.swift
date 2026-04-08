import AppKit
import SwiftUI

enum MemoryConstellationTheme {
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

struct MemoryConstellationVisualTheme {
    let canvasColors: [Color]
    let surfaceFill: Color
    let elevatedFill: Color
    let surfaceStroke: Color
    let tagFill: Color
    let tagStroke: Color
    let secondarySurfaceFill: Color
    let secondarySurfaceStroke: Color
    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color
    let accent: Color
    let focusAccent: Color
    let focusStroke: Color
    let chipSelectedText: Color
    let screenBorder: Color

    private let vocabularyClusterColor: Color
    private let styleClusterColor: Color
    private let scenesClusterColor: Color

    init(palette: HomeWindowStore.HomeThemePalette) {
        let focusAccent = palette.accent
        let canvasMid = Self.mix(palette.canvasTop, palette.canvasBottom, amount: 0.52)
        let trailingCanvas = palette.isDark
            ? Self.mix(canvasMid, .black, amount: 0.34)
            : Self.mix(palette.canvasBottom, .white, amount: 0.12)

        let accent = Self.mix(focusAccent, palette.accentSecondary, amount: 0.30)
        let surfaceBase = palette.isDark
            ? Self.mix(palette.canvasBottom, focusAccent, amount: 0.14)
            : Self.mix(palette.cardTop, focusAccent, amount: 0.06)
        let elevatedBase = palette.isDark
            ? Self.mix(palette.cardBottom, palette.accentSecondary, amount: 0.20)
            : Self.mix(palette.elevatedFill, focusAccent, amount: 0.08)
        let stroke = palette.isDark
            ? Self.mix(palette.border, focusAccent, amount: 0.28)
            : Self.mix(palette.controlStroke, focusAccent, amount: 0.18)
        let tagFill = palette.isDark
            ? Self.mix(surfaceBase, focusAccent, amount: 0.12)
            : Self.mix(palette.softFill, focusAccent, amount: 0.05)
        let secondarySurfaceFill = palette.isDark
            ? Self.mix(palette.canvasBottom, palette.accentSecondary, amount: 0.10)
            : Self.mix(palette.cardBottom, palette.accentSecondary, amount: 0.05)
        let secondarySurfaceStroke = Self.mix(stroke, palette.accentSecondary, amount: 0.25)

        self.canvasColors = [palette.canvasTop, canvasMid, trailingCanvas]
        self.surfaceFill = surfaceBase
        self.elevatedFill = elevatedBase
        self.surfaceStroke = stroke
        self.tagFill = tagFill
        self.tagStroke = Self.mix(stroke, focusAccent, amount: 0.24)
        self.secondarySurfaceFill = secondarySurfaceFill
        self.secondarySurfaceStroke = secondarySurfaceStroke
        self.primaryText = palette.textPrimary
        self.secondaryText = palette.textSecondary
        self.mutedText = palette.textMuted
        self.accent = accent
        self.focusAccent = focusAccent
        self.focusStroke = Self.mix(focusAccent, palette.highlight, amount: 0.30)
        self.chipSelectedText = palette.isDark ? Color.black.opacity(0.82) : Color.white
        self.screenBorder = Self.mix(stroke, focusAccent, amount: 0.20)
        self.vocabularyClusterColor = focusAccent
        self.styleClusterColor = Self.mix(focusAccent, palette.textPrimary, amount: palette.isDark ? 0.18 : 0.08)
        self.scenesClusterColor = Self.mix(focusAccent, palette.canvasBottom, amount: palette.isDark ? 0.24 : 0.12)
    }

    var canvasBackground: LinearGradient {
        LinearGradient(
            colors: canvasColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func clusterColor(for kind: MemoryConstellationClusterKind) -> Color {
        switch kind {
        case .vocabulary:
            return vocabularyClusterColor
        case .style:
            return styleClusterColor
        case .scenes:
            return scenesClusterColor
        }
    }

    func clusterGlow(for kind: MemoryConstellationClusterKind, emphasis: Double) -> RadialGradient {
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

    private static func mix(_ lhs: Color, _ rhs: Color, amount: CGFloat) -> Color {
        let clamped = min(max(amount, 0), 1)
        let left = NSColor(lhs).usingColorSpace(.deviceRGB) ?? .black
        let right = NSColor(rhs).usingColorSpace(.deviceRGB) ?? .black
        return Color(
            red: Double(left.redComponent + ((right.redComponent - left.redComponent) * clamped)),
            green: Double(left.greenComponent + ((right.greenComponent - left.greenComponent) * clamped)),
            blue: Double(left.blueComponent + ((right.blueComponent - left.blueComponent) * clamped)),
            opacity: Double(left.alphaComponent + ((right.alphaComponent - left.alphaComponent) * clamped))
        )
    }
}

private struct MemoryConstellationVisualThemeKey: EnvironmentKey {
    static let defaultValue = MemoryConstellationVisualTheme(palette: HomeWindowStore.ThemePreset.green.palette)
}

extension EnvironmentValues {
    var memoryConstellationTheme: MemoryConstellationVisualTheme {
        get { self[MemoryConstellationVisualThemeKey.self] }
        set { self[MemoryConstellationVisualThemeKey.self] = newValue }
    }
}

struct MemoryConstellationPanel<Content: View>: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

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
                    .fill(constellationTheme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(constellationTheme.surfaceStroke, lineWidth: 1)
            )
    }
}

struct MemoryConstellationTag: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(constellationTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(constellationTheme.tagFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(constellationTheme.tagStroke, lineWidth: 1)
            )
    }
}

struct MemoryConstellationChip: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? constellationTheme.chipSelectedText : constellationTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            constellationTheme.focusAccent,
                                            constellationTheme.accent
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(constellationTheme.secondarySurfaceFill)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? constellationTheme.focusStroke.opacity(0.85) : constellationTheme.secondarySurfaceStroke,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
