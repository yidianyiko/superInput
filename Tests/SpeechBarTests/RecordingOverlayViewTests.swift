import Testing
import SpeechBarDomain
@testable import SpeechBarApp

@Suite("RecordingOverlayView")
struct RecordingOverlayViewTests {
    @Test
    func decorativeStateUsesFixedMotionValuesWhenReduceMotionIsEnabled() {
        let quietSamples = [
            AudioLevelSample(level: 0.08, peak: 0.12),
            AudioLevelSample(level: 0.11, peak: 0.14),
            AudioLevelSample(level: 0.09, peak: 0.13)
        ]
        let loudSamples = [
            AudioLevelSample(level: 0.92, peak: 0.98),
            AudioLevelSample(level: 0.88, peak: 0.96),
            AudioLevelSample(level: 0.94, peak: 0.99)
        ]

        let animatedState = RecordingOverlayView.decorativeState(
            overlayPhase: .recording,
            reduceMotion: false,
            samples: loudSamples
        )
        let reducedState = RecordingOverlayView.decorativeState(
            overlayPhase: .recording,
            reduceMotion: true,
            samples: loudSamples
        )
        let reducedQuietState = RecordingOverlayView.decorativeState(
            overlayPhase: .recording,
            reduceMotion: true,
            samples: quietSamples
        )
        let reducedMotionIntensity = RecordingOverlayView.reducedMotionDecorativeIntensity

        #expect(animatedState.shouldAnimateTimeline)
        #expect(reducedState.shouldAnimateTimeline == false)
        #expect(reducedState.decorativeIntensity == reducedMotionIntensity)
        #expect(reducedQuietState.decorativeIntensity == reducedMotionIntensity)
        #expect(animatedState.decorativeIntensity != reducedState.decorativeIntensity)
    }

    @Test
    func decorativeStateNeverAnimatesOutsideRecording() {
        let samples = [
            AudioLevelSample(level: 0.45, peak: 0.60)
        ]

        let state = RecordingOverlayView.decorativeState(
            overlayPhase: .finalizing,
            reduceMotion: false,
            samples: samples
        )

        #expect(state.shouldAnimateTimeline == false)
    }
}
