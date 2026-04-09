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

    static func quantizedPointer(_ pointer: CGPoint, step: CGFloat = 0.08) -> CGPoint {
        guard step > 0 else {
            return CGPoint(
                x: clamp(pointer.x, min: -1, max: 1),
                y: clamp(pointer.y, min: -1, max: 1)
            )
        }

        func quantize(_ value: CGFloat) -> CGFloat {
            let clamped = clamp(value, min: -1, max: 1)
            return (clamped / step).rounded() * step
        }

        return CGPoint(
            x: quantize(pointer.x),
            y: quantize(pointer.y)
        )
    }

    static func showcasePointer(
        phase: TimeInterval,
        activationProgress: CGFloat
    ) -> CGPoint {
        let remaining = max(0, 1 - activationProgress)
        guard remaining > 0.001 else {
            return .zero
        }

        let envelope = remaining * remaining
        return CGPoint(
            x: CGFloat(sin(phase * 1.9)) * 0.34 * envelope,
            y: CGFloat(cos((phase * 1.5) + 0.8)) * 0.24 * envelope
        )
    }

    static func chaosStarOffset(
        cluster: MemoryConstellationClusterKind,
        starIndex: Int,
        activationProgress: CGFloat
    ) -> CGSize {
        let remaining = max(0, 1 - activationProgress)
        guard remaining > 0.001 else {
            return .zero
        }

        let seed = cluster.motionSeed + Double(starIndex) * 1.17
        let envelope = Double(remaining * remaining)
        let horizontal = sin((1 - Double(activationProgress)) * 10.4 + (seed * 1.8))
            + (cos((1 - Double(activationProgress)) * 18.6 + (seed * 0.9)) * 0.42)
        let vertical = cos((1 - Double(activationProgress)) * 9.1 + (seed * 1.5))
            + (sin((1 - Double(activationProgress)) * 20.8 + (seed * 0.7)) * 0.36)
        let horizontalAmplitude = 34.0 + Double(starIndex % 3) * 12.0
        let verticalAmplitude = 28.0 + Double((starIndex + 1) % 4) * 10.0

        return CGSize(
            width: horizontal * horizontalAmplitude * envelope,
            height: vertical * verticalAmplitude * envelope
        )
    }

    static func chaosBridgeOffset(
        bridgeIndex: Int,
        activationProgress: CGFloat
    ) -> CGSize {
        let remaining = max(0, 1 - activationProgress)
        guard remaining > 0.001 else {
            return .zero
        }

        let seed = Double(bridgeIndex) * 1.31
        let envelope = Double(remaining * remaining)
        return CGSize(
            width: sin((1 - Double(activationProgress)) * 8.6 + seed) * 18 * envelope,
            height: cos((1 - Double(activationProgress)) * 7.4 + (seed * 1.4)) * 14 * envelope
        )
    }

    static func shouldAnimateTimeline(
        reduceMotion: Bool,
        capturePulseProgress: CGFloat,
        activationProgress: CGFloat
    ) -> Bool {
        guard reduceMotion == false else {
            return false
        }

        let pulseActive = capturePulseProgress > 0.001
        let activationActive = activationProgress < 0.999

        return pulseActive || activationActive
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
