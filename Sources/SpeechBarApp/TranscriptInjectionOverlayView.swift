import SwiftUI
import SpeechBarDomain

struct TranscriptInjectionOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: TranscriptInjectionOverlayStore

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: store.presentation == nil)) { context in
                ZStack {
                    if let presentation = store.presentation {
                        let localScreenFrame = CGRect(origin: .zero, size: proxy.size)
                        let source = TranscriptInjectionOverlayMotion.sourcePoint(for: localScreenFrame)
                        let destination = CGPoint(
                            x: presentation.target.destinationPoint.x - presentation.target.screenFrame.minX,
                            y: presentation.target.destinationPoint.y - presentation.target.screenFrame.minY
                        )
                        let progress = min(
                            max(
                                context.date.timeIntervalSince(presentation.startedAt)
                                / TranscriptInjectionOverlayMotion.visibleDuration,
                                0
                            ),
                            1
                        )
                        let particles = TranscriptInjectionOverlayMotion.particles(reduceMotion: reduceMotion)
                        let markerColor = markerColor(for: presentation.endingStyle)

                        ForEach(particles) { particle in
                            Circle()
                                .fill(markerColor.opacity(0.94))
                                .frame(width: particle.size, height: particle.size)
                                .opacity(
                                    TranscriptInjectionOverlayMotion.particleOpacity(
                                        progress: progress,
                                        particle: particle
                                    )
                                )
                                .position(
                                    TranscriptInjectionOverlayMotion.position(
                                        for: particle,
                                        progress: progress,
                                        source: source,
                                        destination: destination
                                    )
                                )
                        }

                        Circle()
                            .stroke(markerColor, lineWidth: markerLineWidth(for: presentation.endingStyle))
                            .frame(width: 34, height: 34)
                            .scaleEffect(
                                TranscriptInjectionOverlayMotion.markerScale(
                                    progress: progress,
                                    endingStyle: presentation.endingStyle
                                )
                            )
                            .opacity(
                                TranscriptInjectionOverlayMotion.markerOpacity(
                                    progress: progress,
                                    endingStyle: presentation.endingStyle
                                )
                            )
                            .position(destination)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(Color.clear)
    }

    private func markerColor(
        for endingStyle: TranscriptInjectionOverlayEndingStyle
    ) -> Color {
        switch endingStyle {
        case .success:
            return Color(red: 0.48, green: 0.93, blue: 0.73)
        case .downgraded:
            return Color(red: 1.0, green: 0.78, blue: 0.38)
        }
    }

    private func markerLineWidth(
        for endingStyle: TranscriptInjectionOverlayEndingStyle
    ) -> CGFloat {
        switch endingStyle {
        case .success:
            return 2.5
        case .downgraded:
            return 2
        }
    }
}
