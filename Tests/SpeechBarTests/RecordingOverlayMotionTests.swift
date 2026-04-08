import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarApp

@Suite("RecordingOverlayMotion")
struct RecordingOverlayMotionTests {
    @Test
    func audioIntensityIsZeroForEmptySamples() {
        #expect(RecordingOverlayMotion.audioIntensity(from: []) == 0)
    }

    @Test
    func audioIntensityTracksRecentAverageAndPeakWithinBounds() {
        let samples = [
            AudioLevelSample(level: 0.10, peak: 0.15),
            AudioLevelSample(level: 0.22, peak: 0.30),
            AudioLevelSample(level: 0.48, peak: 0.62),
            AudioLevelSample(level: 0.72, peak: 0.90)
        ]

        let intensity = RecordingOverlayMotion.audioIntensity(from: samples)

        #expect(intensity > 0.40)
        #expect(intensity < 0.95)
    }

    @Test
    func starOffsetsStaySubtleButMoveAcrossPhases() {
        let early = RecordingOverlayMotion.starOffset(index: 2, phase: 0, intensity: 0.45)
        let later = RecordingOverlayMotion.starOffset(index: 2, phase: 2.4, intensity: 0.45)

        #expect(abs(early.width - later.width) > 0.05 || abs(early.height - later.height) > 0.05)
        #expect(abs(early.width) <= 4.0)
        #expect(abs(early.height) <= 2.5)
        #expect(abs(later.width) <= 4.0)
        #expect(abs(later.height) <= 2.5)
    }

    @Test
    func edgeGlowStrengthIncreasesAsAudioIntensityRises() {
        let quiet = RecordingOverlayMotion.edgeGlowOpacity(intensity: 0.10)
        let loud = RecordingOverlayMotion.edgeGlowOpacity(intensity: 0.90)

        #expect(loud > quiet)
        #expect(quiet >= 0.10)
        #expect(loud <= 0.28)
    }
}
