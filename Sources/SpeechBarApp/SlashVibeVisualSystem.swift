import SwiftUI

struct SlashVibeCanvas: View {
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        ZStack {
            palette.canvasTop
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.30),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    palette.accent.opacity(0.05),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 280
            )
            .ignoresSafeArea()
        }
    }
}

private struct SlashVibeSurfaceModifier: ViewModifier {
    let palette: HomeWindowStore.HomeThemePalette
    let cornerRadius: CGFloat
    let accent: Color?

    func body(content: Content) -> some View {
        let shadowColor = Color.black.opacity(0.08)
        let edgeAccent = (accent ?? palette.accent).opacity(0.08)

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.cardTop,
                                palette.cardBottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.86), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.border, lineWidth: 1)
                            .padding(0.5)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(edgeAccent, lineWidth: 1)
                            .blur(radius: 0.3)
                    }
                    .shadow(color: shadowColor, radius: 18, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
    }
}

private struct SlashVibeHeroSurfaceModifier: ViewModifier {
    let palette: HomeWindowStore.HomeThemePalette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.975, green: 0.978, blue: 0.985)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RadialGradient(
                            colors: [
                                palette.accent.opacity(0.08),
                                Color.white.opacity(0.30),
                                .clear
                            ],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 260
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            .padding(0.5)
                    )
                    .shadow(color: Color.black.opacity(0.09), radius: 24, x: 0, y: 16)
                    .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
    }
}

extension View {
    func slashVibeSurface(
        palette: HomeWindowStore.HomeThemePalette,
        cornerRadius: CGFloat = 22,
        accent: Color? = nil
    ) -> some View {
        modifier(
            SlashVibeSurfaceModifier(
                palette: palette,
                cornerRadius: cornerRadius,
                accent: accent
            )
        )
    }

    func slashVibeHeroSurface(
        palette: HomeWindowStore.HomeThemePalette,
        cornerRadius: CGFloat = 28
    ) -> some View {
        modifier(
            SlashVibeHeroSurfaceModifier(
                palette: palette,
                cornerRadius: cornerRadius
            )
        )
    }
}

struct SlashVibeHeroSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
            .opacity(configuration.isPressed ? 0.82 : 1.0)
    }
}
