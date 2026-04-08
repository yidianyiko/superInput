import CoreGraphics
import Foundation

enum MemoryConstellationMotion {
    static func starOffset(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> CGSize {
        let seed = cluster.motionSeed + Double(starIndex) * 0.91
        let horizontalAmplitude = 4.0 + Double(starIndex % 3) * 1.8
        let verticalAmplitude = 3.4 + Double((starIndex + 1) % 4) * 1.5

        return CGSize(
            width: sin((phase * 0.72) + seed) * horizontalAmplitude,
            height: cos((phase * 0.58) + (seed * 1.37)) * verticalAmplitude
        )
    }

    static func starScale(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> CGFloat {
        let shimmer = 0.032 * sin((phase * 0.94) + cluster.motionSeed + Double(starIndex) * 0.63)
        return 1 + shimmer
    }

    static func starOpacity(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        phase: TimeInterval
    ) -> Double {
        let shimmer = 0.12 * sin((phase * 1.18) + cluster.motionSeed + Double(starIndex) * 0.41)
        return min(max(0.74 + shimmer, 0.58), 0.94)
    }

    static func bridgeLift(bridgeIndex: Int, phase: TimeInterval) -> CGFloat {
        CGFloat(4 + (sin((phase * 0.66) + Double(bridgeIndex) * 0.9) * 3.2))
    }

    static func ambientOpacity(index: Int, phase: TimeInterval) -> Double {
        let base = index.isMultiple(of: 5) ? 0.22 : 0.10
        let shimmer = 0.06 * sin((phase * 0.48) + Double(index) * 0.37)
        return min(max(base + shimmer, 0.05), 0.30)
    }

    static func clusterBreath(cluster: MemoryConstellationClusterKind, phase: TimeInterval) -> CGFloat {
        CGFloat(0.018 * sin((phase * 0.52) + cluster.motionSeed))
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
