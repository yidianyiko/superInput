import AppKit
import Foundation
import SwiftUI
import Testing
import SpeechBarDomain
@testable import SpeechBarApp
import SpeechBarApplication

@Suite("RecordingOverlayView", .serialized)
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

    @Test
    @MainActor
    func recordingPhaseHostsInNSHostingView() async throws {
        let dependencies = makeRecordingOverlayDependencies()
        dependencies.coordinator.start()

        dependencies.hardware.send(
            HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed)
        )

        try await eventually {
            dependencies.coordinator.sessionState == .recording
        }

        dependencies.audio.emit(
            level: AudioLevelSample(level: 0.32, peak: 0.48)
        )

        let hostingView = makeHostingView(coordinator: dependencies.coordinator)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.fittingSize == CGSize(width: 172, height: 52))
    }

    @Test
    @MainActor
    func finalizingPhaseHostsInNSHostingView() async throws {
        let dependencies = makeRecordingOverlayDependencies(finalizeDelay: .milliseconds(200))
        dependencies.coordinator.start()

        dependencies.hardware.send(
            HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed)
        )

        try await eventually {
            dependencies.coordinator.sessionState == .recording
        }

        let hostingView = makeHostingView(coordinator: dependencies.coordinator)
        hostingView.layoutSubtreeIfNeeded()
        #expect(hostingView.fittingSize == CGSize(width: 172, height: 52))

        dependencies.coordinator.finalizeCaptureFromOverlay()

        try await eventually {
            dependencies.coordinator.sessionState == .finalizing
        }

        hostingView.layoutSubtreeIfNeeded()
        #expect(hostingView.fittingSize == CGSize(width: 132, height: 40))
    }

    @Test
    @MainActor
    func recordingPhaseHostsInReduceMotionEnvironment() async throws {
        let dependencies = makeRecordingOverlayDependencies()
        dependencies.coordinator.start()

        dependencies.hardware.send(
            HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed)
        )

        try await eventually {
            dependencies.coordinator.sessionState == .recording
        }

        dependencies.audio.emit(
            level: AudioLevelSample(level: 0.78, peak: 0.84)
        )
        dependencies.audio.emit(
            level: AudioLevelSample(level: 0.56, peak: 0.71)
        )

        let hostingView = makeHostingView(
            coordinator: dependencies.coordinator,
            reduceMotion: true
        )
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.fittingSize == CGSize(width: 172, height: 52))
    }
}

@MainActor
private func makeRecordingOverlayDependencies(
    finalizeDelay: Duration? = nil
) -> RecordingOverlayViewTestDependencies {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    client.finalizeDelay = finalizeDelay
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        sleepClock: ImmediateSleepClock()
    )

    return RecordingOverlayViewTestDependencies(
        coordinator: coordinator,
        hardware: hardware,
        audio: audio
    )
}

@MainActor
private func makeHostingView(
    coordinator: VoiceSessionCoordinator,
    reduceMotion: Bool = false
) -> NSHostingView<AnyView> {
    NSHostingView(
        rootView: AnyView(
            RecordingOverlayView(coordinator: coordinator)
                .environment(\._accessibilityReduceMotion, reduceMotion)
        )
    )
}

@MainActor
private struct RecordingOverlayViewTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let hardware: MockHardwareEventSource
    let audio: MockAudioInputSource
}

private enum TestFailure: Error {
    case timeout
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(20),
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if predicate() {
            return
        }
        try await clock.sleep(for: pollInterval)
    }

    throw TestFailure.timeout
}
