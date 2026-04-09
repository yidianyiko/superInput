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
                        let markerStyle = markerStyle(for: presentation.endingStyle)
                        let markerScale = TranscriptInjectionOverlayMotion.markerScale(
                            progress: progress,
                            endingStyle: presentation.endingStyle
                        )

                        ForEach(particles) { particle in
                            Circle()
                                .fill(Color.white.opacity(0.96))
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
                            .stroke(markerStyle.color, lineWidth: markerStyle.lineWidth)
                            .frame(width: 26 * markerScale, height: 26 * markerScale)
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

    private func markerStyle(
        for endingStyle: TranscriptInjectionOverlayEndingStyle
    ) -> (color: Color, lineWidth: CGFloat) {
        switch endingStyle {
        case .success:
            return (
                color: Color.white.opacity(0.9),
                lineWidth: 1.6
            )
        case .downgraded:
            return (
                color: Color(red: 0.74, green: 0.86, blue: 1.0).opacity(0.92),
                lineWidth: 2.0
            )
        }
    }
}
