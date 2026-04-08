import CoreGraphics
import Foundation
import SpeechBarDomain

enum RecordingOverlayMotion {
    struct AmbientStar: Equatable {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let seed: Double
    }

    static let ambientStars: [AmbientStar] = [
        .init(x: 0.16, y: 0.30, size: 2.0, seed: 0.2),
        .init(x: 0.24, y: 0.66, size: 1.8, seed: 0.8),
        .init(x: 0.34, y: 0.38, size: 1.6, seed: 1.4),
        .init(x: 0.47, y: 0.72, size: 1.8, seed: 2.0),
        .init(x: 0.56, y: 0.28, size: 2.0, seed: 2.7),
        .init(x: 0.66, y: 0.60, size: 1.5, seed: 3.1),
        .init(x: 0.77, y: 0.34, size: 1.9, seed: 3.8),
        .init(x: 0.84, y: 0.68, size: 1.7, seed: 4.5)
    ]

    static func audioIntensity(from samples: [AudioLevelSample]) -> Double {
        guard !samples.isEmpty else { return 0 }

        let recentSamples = Array(samples.suffix(6))
        let averageLevel = recentSamples.reduce(0) { $0 + $1.level } / Double(recentSamples.count)
        let recentPeak = recentSamples.reduce(0) { max($0, $1.peak) }

        return min(max((averageLevel * 0.65) + (recentPeak * 0.35), 0), 1)
    }

    static func starOffset(index: Int, phase: TimeInterval, intensity: Double) -> CGSize {
        let clampedIntensity = min(max(intensity, 0), 1)
        let seed = ambientStars[index % ambientStars.count].seed
        let amplitude = 1.2 + Double(index % 3) * 0.45 + (clampedIntensity * 0.85)

        return CGSize(
            width: sin((phase * 0.52) + seed) * amplitude,
            height: cos((phase * 0.44) + (seed * 1.31)) * (amplitude * 0.55)
        )
    }

    static func edgeGlowOpacity(intensity: Double) -> Double {
        let clampedIntensity = min(max(intensity, 0), 1)
        return 0.10 + (clampedIntensity * 0.18)
    }
}
