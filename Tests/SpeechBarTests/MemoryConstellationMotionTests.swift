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
    func quantizedPointerSuppressesTinyMouseJitter() {
        let quiet = MemoryConstellationMotion.quantizedPointer(
            CGPoint(x: 0.04, y: -0.03),
            step: 0.1
        )
        let shifted = MemoryConstellationMotion.quantizedPointer(
            CGPoint(x: 0.37, y: -0.44),
            step: 0.1
        )

        #expect(abs(quiet.x) < 0.001)
        #expect(abs(quiet.y) < 0.001)
        #expect(abs(shifted.x - 0.4) < 0.001)
        #expect(abs(shifted.y + 0.4) < 0.001)
    }

    @Test
    func showcasePointerFallsBackToRestAfterIntroCompletes() {
        let active = MemoryConstellationMotion.showcasePointer(
            phase: 1.1,
            activationProgress: 0.35
        )
        let settled = MemoryConstellationMotion.showcasePointer(
            phase: 1.1,
            activationProgress: 1
        )

        #expect(abs(active.x) > 0.01 || abs(active.y) > 0.01)
        #expect(abs(settled.x) < 0.001)
        #expect(abs(settled.y) < 0.001)
    }

    @Test
    func chaosOffsetsStartWildAndSettleBackToZero() {
        let starChaos = MemoryConstellationMotion.chaosStarOffset(
            cluster: .scenes,
            starIndex: 4,
            activationProgress: 0.15
        )
        let starSettled = MemoryConstellationMotion.chaosStarOffset(
            cluster: .scenes,
            starIndex: 4,
            activationProgress: 1
        )
        let bridgeChaos = MemoryConstellationMotion.chaosBridgeOffset(
            bridgeIndex: 1,
            activationProgress: 0.2
        )
        let bridgeSettled = MemoryConstellationMotion.chaosBridgeOffset(
            bridgeIndex: 1,
            activationProgress: 1
        )

        #expect(abs(starChaos.width) > 8 || abs(starChaos.height) > 8)
        #expect(abs(starSettled.width) < 0.001)
        #expect(abs(starSettled.height) < 0.001)
        #expect(abs(bridgeChaos.width) > 4 || abs(bridgeChaos.height) > 4)
        #expect(abs(bridgeSettled.width) < 0.001)
        #expect(abs(bridgeSettled.height) < 0.001)
    }

    @Test
    func timelineAnimationOnlyRunsDuringIntroOrPulse() {
        let idle = MemoryConstellationMotion.shouldAnimateTimeline(
            reduceMotion: false,
            capturePulseProgress: 0,
            activationProgress: 1
        )
        let pulsing = MemoryConstellationMotion.shouldAnimateTimeline(
            reduceMotion: false,
            capturePulseProgress: 0.4,
            activationProgress: 1
        )
        let activating = MemoryConstellationMotion.shouldAnimateTimeline(
            reduceMotion: false,
            capturePulseProgress: 0,
            activationProgress: 0.6
        )
        let reduced = MemoryConstellationMotion.shouldAnimateTimeline(
            reduceMotion: true,
            capturePulseProgress: 0.6,
            activationProgress: 0.4
        )

        #expect(idle == false)
        #expect(pulsing == true)
        #expect(activating == true)
        #expect(reduced == false)
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
