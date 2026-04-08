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
    func audioIntensityStaysWithinUnitRange() {
        let samples = [
            AudioLevelSample(level: 1.2, peak: 1.5),
            AudioLevelSample(level: 0.88, peak: 1.1),
            AudioLevelSample(level: 0.95, peak: 1.4),
            AudioLevelSample(level: 1.0, peak: 1.8)
        ]

        let intensity = RecordingOverlayMotion.audioIntensity(from: samples)

        #expect(intensity >= 0)
        #expect(intensity <= 1)
    }

    @Test
    func audioIntensityIgnoresSamplesOutsideTheRecentWindow() {
        let historicalSamples = [
            AudioLevelSample(level: 0.95, peak: 0.98),
            AudioLevelSample(level: 0.90, peak: 0.92)
        ]
        let recentSamples = [
            AudioLevelSample(level: 0.10, peak: 0.12),
            AudioLevelSample(level: 0.16, peak: 0.18),
            AudioLevelSample(level: 0.12, peak: 0.14),
            AudioLevelSample(level: 0.08, peak: 0.10),
            AudioLevelSample(level: 0.15, peak: 0.17),
            AudioLevelSample(level: 0.11, peak: 0.13)
        ]

        let intensityWithHistory = RecordingOverlayMotion.audioIntensity(from: historicalSamples + recentSamples)
        let intensityFromRecentSamplesOnly = RecordingOverlayMotion.audioIntensity(from: recentSamples)

        #expect(intensityWithHistory == intensityFromRecentSamplesOnly)
        #expect(intensityWithHistory >= 0)
        #expect(intensityWithHistory <= 1)
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
