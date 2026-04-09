import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationMotion")
struct MemoryConstellationMotionTests {
    @Test
    func normalizedPointerMapsCenterToNeutralVectorAndClampsEdges() {
        let neutral = MemoryConstellationMotion.normalizedPointer(
            location: CGPoint(x: 120, y: 90),
            in: CGSize(width: 240, height: 180)
        )
        let edge = MemoryConstellationMotion.normalizedPointer(
            location: CGPoint(x: 400, y: -100),
            in: CGSize(width: 240, height: 180)
        )

        #expect(abs(neutral.x) < 0.001)
        #expect(abs(neutral.y) < 0.001)
        #expect(edge.x == 1)
        #expect(edge.y == -1)
    }

    @Test
    func parallaxOffsetUsesConfiguredDepth() {
        let offset = MemoryConstellationMotion.parallaxOffset(
            pointerVector: CGPoint(x: 0.75, y: -0.5),
            maxX: 20,
            maxY: 12
        )

        #expect(offset.width == 15)
        #expect(offset.height == -6)
    }

    @Test
    func starOffsetsShiftAcrossPhasesWithinSmallDriftBounds() {
        let early = MemoryConstellationMotion.starOffset(
            cluster: .vocabulary,
            starIndex: 2,
            phase: 0
        )
        let later = MemoryConstellationMotion.starOffset(
            cluster: .vocabulary,
            starIndex: 2,
            phase: 2.4
        )

        #expect(abs(early.width - later.width) > 0.1 || abs(early.height - later.height) > 0.1)
        #expect(abs(early.width) <= 14)
        #expect(abs(early.height) <= 14)
        #expect(abs(later.width) <= 14)
        #expect(abs(later.height) <= 14)
    }

    @Test
    func clusterAndBridgeMotionReadAsEnergyBurstInsteadOfSubtleIdleDrift() {
        let earlyBreath = MemoryConstellationMotion.clusterBreath(cluster: .style, phase: 0)
        let laterBreath = MemoryConstellationMotion.clusterBreath(cluster: .style, phase: 4.4)

        let earlyLift = MemoryConstellationMotion.bridgeLift(bridgeIndex: 1, phase: 0)
        let laterLift = MemoryConstellationMotion.bridgeLift(bridgeIndex: 1, phase: 4.4)

        #expect(abs(earlyBreath - laterBreath) >= 0.035)
        #expect(abs(earlyLift - laterLift) >= 4.5)
    }
}
