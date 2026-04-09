import CoreGraphics
import Foundation

enum MemoryConstellationMotion {
    static func normalizedPointer(location: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else {
            return .zero
        }

        let normalizedX = ((location.x / size.width) * 2) - 1
        let normalizedY = ((location.y / size.height) * 2) - 1

        return CGPoint(
            x: clamp(normalizedX, min: -1, max: 1),
            y: clamp(normalizedY, min: -1, max: 1)
        )
    }

    static func parallaxOffset(
        pointerVector: CGPoint,
        maxX: CGFloat,
        maxY: CGFloat
    ) -> CGSize {
        CGSize(
            width: clamp(pointerVector.x, min: -1, max: 1) * maxX,
            height: clamp(pointerVector.y, min: -1, max: 1) * maxY
        )
    }

    static func starOffset(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> CGSize {
        let seed = cluster.motionSeed + Double(starIndex) * 0.91
        let horizontalAmplitude = 5.2 + Double(starIndex % 3) * 1.6
        let verticalAmplitude = 4.4 + Double((starIndex + 1) % 4) * 1.2

        return CGSize(
            width: sin((phase * 0.88) + seed) * horizontalAmplitude,
            height: cos((phase * 0.72) + (seed * 1.37)) * verticalAmplitude
        )
    }

    static func starScale(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> CGFloat {
        let shimmer = 0.058 * sin((phase * 1.12) + cluster.motionSeed + Double(starIndex) * 0.63)
        return 1 + shimmer
    }

    static func starOpacity(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> Double {
        let shimmer = 0.18 * sin((phase * 1.34) + cluster.motionSeed + Double(starIndex) * 0.41)
        return min(max(0.78 + shimmer, 0.52), 0.98)
    }

    static func bridgeLift(bridgeIndex: Int, phase: TimeInterval) -> CGFloat {
        CGFloat(5.6 + (sin((phase * 0.82) + Double(bridgeIndex) * 0.9) * 4.4))
    }

    static func bridgeEnergyPhase(bridgeIndex: Int, phase: TimeInterval) -> CGFloat {
        CGFloat((phase * 126) + Double(bridgeIndex) * 34)
    }

    static func ambientOpacity(index: Int, phase: TimeInterval) -> Double {
        let base = index.isMultiple(of: 5) ? 0.22 : 0.10
        let shimmer = 0.08 * sin((phase * 0.62) + Double(index) * 0.37)
        return min(max(base + shimmer, 0.05), 0.34)
    }

    static func clusterBreath(cluster: MemoryConstellationClusterKind, phase: TimeInterval) -> CGFloat {
        CGFloat(0.032 * sin((phase * 0.72) + cluster.motionSeed))
    }

    static func energyRingRotation(cluster: MemoryConstellationClusterKind, phase: TimeInterval) -> CGFloat {
        CGFloat((phase * 24) + (cluster.motionSeed * 18))
    }

    static func energyRingScale(
        cluster: MemoryConstellationClusterKind,
        phase: TimeInterval,
        activationProgress: CGFloat
    ) -> CGFloat {
        let activationBoost = (1 - activationProgress) * 0.24
        let breath = clusterBreath(cluster: cluster, phase: phase) * 1.8
        return 1 + activationBoost + breath
    }

    private static func clamp<T: Comparable>(_ value: T, min minimum: T, max maximum: T) -> T {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

private extension MemoryConstellationClusterKind {
    var motionSeed: Double {
        switch self {
        case .vocabulary:
            return 0.9
        case .style:
            return 2.4
        case .scenes:
            return 4.1
        }
    }
}
