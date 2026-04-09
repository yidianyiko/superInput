import CoreGraphics
import Foundation

enum TranscriptInjectionOverlayEndingStyle: Equatable {
    case success
    case downgraded
}

struct TranscriptInjectionOverlayParticle: Equatable, Identifiable {
    let id: Int
    let spawnOffset: CGSize
    let controlOffset: CGSize
    let size: CGFloat
    let opacity: Double
}

enum TranscriptInjectionOverlayMotion {
    static let visibleDuration: TimeInterval = 0.62

    private static let baseParticles: [TranscriptInjectionOverlayParticle] = [
        .init(id: 0, spawnOffset: CGSize(width: -28, height: -6), controlOffset: CGSize(width: -46, height: 120), size: 4, opacity: 0.96),
        .init(id: 1, spawnOffset: CGSize(width: -18, height: 8), controlOffset: CGSize(width: -24, height: 146), size: 3, opacity: 0.88),
        .init(id: 2, spawnOffset: CGSize(width: -8, height: -10), controlOffset: CGSize(width: -8, height: 138), size: 3, opacity: 0.90),
        .init(id: 3, spawnOffset: CGSize(width: 0, height: 10), controlOffset: CGSize(width: 0, height: 154), size: 4, opacity: 0.98),
        .init(id: 4, spawnOffset: CGSize(width: 8, height: -12), controlOffset: CGSize(width: 12, height: 144), size: 3, opacity: 0.92),
        .init(id: 5, spawnOffset: CGSize(width: 18, height: 6), controlOffset: CGSize(width: 28, height: 132), size: 3, opacity: 0.86),
        .init(id: 6, spawnOffset: CGSize(width: 28, height: -4), controlOffset: CGSize(width: 44, height: 116), size: 4, opacity: 0.95),
        .init(id: 7, spawnOffset: CGSize(width: -34, height: 14), controlOffset: CGSize(width: -58, height: 110), size: 2, opacity: 0.80),
        .init(id: 8, spawnOffset: CGSize(width: -12, height: 18), controlOffset: CGSize(width: -18, height: 128), size: 2, opacity: 0.82),
        .init(id: 9, spawnOffset: CGSize(width: 14, height: 18), controlOffset: CGSize(width: 16, height: 124), size: 2, opacity: 0.84),
        .init(id: 10, spawnOffset: CGSize(width: 34, height: 12), controlOffset: CGSize(width: 56, height: 108), size: 2, opacity: 0.80),
        .init(id: 11, spawnOffset: CGSize(width: 0, height: -18), controlOffset: CGSize(width: 0, height: 160), size: 2, opacity: 0.78)
    ]

    static func sourcePoint(for screenFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenFrame.midX,
            y: screenFrame.minY + (screenFrame.height * 0.16)
        )
    }

    static func particles(reduceMotion: Bool) -> [TranscriptInjectionOverlayParticle] {
        if reduceMotion {
            return Array(baseParticles.prefix(8))
        }

        return baseParticles
    }

    static func position(
        for particle: TranscriptInjectionOverlayParticle,
        progress: Double,
        source: CGPoint,
        destination: CGPoint
    ) -> CGPoint {
        let clampedProgress = clampProgress(progress)
        let start = CGPoint(
            x: source.x + particle.spawnOffset.width,
            y: source.y + particle.spawnOffset.height
        )
        let control = CGPoint(
            x: ((source.x + destination.x) / 2) + particle.controlOffset.width,
            y: max(source.y, destination.y) + particle.controlOffset.height
        )
        let t = clampedProgress
        let oneMinusT = 1 - t

        return CGPoint(
            x: (oneMinusT * oneMinusT * start.x) + (2 * oneMinusT * t * control.x) + (t * t * destination.x),
            y: (oneMinusT * oneMinusT * start.y) + (2 * oneMinusT * t * control.y) + (t * t * destination.y)
        )
    }

    static func particleOpacity(progress: Double, particle: TranscriptInjectionOverlayParticle) -> Double {
        let clampedProgress = clampProgress(progress)
        return max(0, particle.opacity * (1 - (clampedProgress * 0.72)))
    }

    static func markerScale(progress: Double, endingStyle: TranscriptInjectionOverlayEndingStyle) -> CGFloat {
        let clampedProgress = clampProgress(progress)

        switch endingStyle {
        case .success:
            return CGFloat(0.72 + (0.28 * sin(clampedProgress * .pi)))
        case .downgraded:
            return CGFloat(0.54 + (0.42 * sin(clampedProgress * .pi * 1.5)))
        }
    }

    static func markerOpacity(progress: Double, endingStyle: TranscriptInjectionOverlayEndingStyle) -> Double {
        let clampedProgress = clampProgress(progress)

        switch endingStyle {
        case .success:
            return max(0, 1 - abs(clampedProgress - 0.92) * 8)
        case .downgraded:
            return max(0, 1 - abs(clampedProgress - 0.94) * 10)
        }
    }

    private static func clampProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}
