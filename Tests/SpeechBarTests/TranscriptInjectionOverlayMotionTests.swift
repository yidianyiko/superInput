import Foundation
import Testing
@testable import SpeechBarApp

@Suite("TranscriptInjectionOverlayMotion")
struct TranscriptInjectionOverlayMotionTests {
    @Test
    func sourcePointAnchorsNearTheLowerCenterOfTheScreen() {
        let sourcePoint = TranscriptInjectionOverlayMotion.sourcePoint(
            for: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(sourcePoint.x == 720)
        #expect(sourcePoint.y == 144)
    }

    @Test
    func reduceMotionUsesFewerParticles() {
        let animatedParticles = TranscriptInjectionOverlayMotion.particles(reduceMotion: false)
        let reducedParticles = TranscriptInjectionOverlayMotion.particles(reduceMotion: true)

        #expect(animatedParticles.count == 12)
        #expect(reducedParticles.count == 8)
    }

    @Test
    func particlePositionMovesTowardDestinationAcrossProgress() {
        let particle = TranscriptInjectionOverlayMotion.particles(reduceMotion: false)[0]
        let source = CGPoint(x: 720, y: 144)
        let destination = CGPoint(x: 920, y: 580)

        let early = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: 0.10,
            source: source,
            destination: destination
        )
        let late = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: 0.90,
            source: source,
            destination: destination
        )

        #expect(late.x > early.x)
        #expect(late.y > early.y)
    }

    @Test
    func downgradedEndingUsesDifferentMarkerScaleThanSuccess() {
        let success = TranscriptInjectionOverlayMotion.markerScale(
            progress: 0.96,
            endingStyle: .success
        )
        let downgraded = TranscriptInjectionOverlayMotion.markerScale(
            progress: 0.96,
            endingStyle: .downgraded
        )

        #expect(success != downgraded)
        #expect(success > 0)
        #expect(downgraded > 0)
    }
}
