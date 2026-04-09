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
    func particlesMatchTheExpectedFixtureDefinitions() {
        let particles = TranscriptInjectionOverlayMotion.particles(reduceMotion: false)
        let first = particles.first
        let last = particles.last

        guard let first else {
            Issue.record("Expected a first particle.")
            return
        }

        guard let last else {
            Issue.record("Expected a last particle.")
            return
        }

        #expect(first == TranscriptInjectionOverlayParticle(
            id: 0,
            spawnOffset: CGSize(width: -28, height: -6),
            controlOffset: CGSize(width: -46, height: 120),
            size: 4,
            opacity: 0.96
        ))
        #expect(last == TranscriptInjectionOverlayParticle(
            id: 11,
            spawnOffset: CGSize(width: 0, height: -18),
            controlOffset: CGSize(width: 0, height: 160),
            size: 2,
            opacity: 0.78
        ))
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
    func positionClampsProgressAndUsesEndpoints() {
        let particle = TranscriptInjectionOverlayMotion.particles(reduceMotion: false)[0]
        let source = CGPoint(x: 720, y: 144)
        let destination = CGPoint(x: 920, y: 580)
        let expectedStart = CGPoint(
            x: source.x + particle.spawnOffset.width,
            y: source.y + particle.spawnOffset.height
        )

        let start = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: 0,
            source: source,
            destination: destination
        )
        let clampedLow = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: -1,
            source: source,
            destination: destination
        )
        let end = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: 1,
            source: source,
            destination: destination
        )
        let clampedHigh = TranscriptInjectionOverlayMotion.position(
            for: particle,
            progress: 2,
            source: source,
            destination: destination
        )

        #expect(start == expectedStart)
        #expect(clampedLow == start)
        #expect(end == destination)
        #expect(clampedHigh == end)
    }

    @Test
    func opacityOutputsMatchTheExpectedCurves() {
        let particle = TranscriptInjectionOverlayMotion.particles(reduceMotion: false)[3]

        let opacityAtStart = TranscriptInjectionOverlayMotion.particleOpacity(
            progress: 0,
            particle: particle
        )
        let opacityAtEnd = TranscriptInjectionOverlayMotion.particleOpacity(
            progress: 1,
            particle: particle
        )
        let successMarkerOpacity = TranscriptInjectionOverlayMotion.markerOpacity(
            progress: 0.94,
            endingStyle: .success
        )
        let downgradedMarkerOpacity = TranscriptInjectionOverlayMotion.markerOpacity(
            progress: 0.94,
            endingStyle: .downgraded
        )

        #expect(opacityAtStart == particle.opacity)
        #expect(opacityAtEnd == particle.opacity * 0.28)
        #expect(successMarkerOpacity >= 0)
        #expect(downgradedMarkerOpacity >= 0)
        #expect(successMarkerOpacity != downgradedMarkerOpacity)
    }

    @Test
    func sourcePointAnchorsFromTheScreenOriginIndependentOfZeroBasedFrames() {
        let sourcePoint = TranscriptInjectionOverlayMotion.sourcePoint(
            for: CGRect(x: 120, y: 80, width: 1280, height: 720)
        )

        #expect(abs(sourcePoint.x - 760) < 0.0001)
        #expect(abs(sourcePoint.y - 195.2) < 0.0001)
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
