import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain

@Suite("TranscriptInjectionOverlayController", .serialized)
struct TranscriptInjectionOverlayControllerTests {
    @Test
    @MainActor
    func startedEventShowsPanelOnTargetScreenFrame() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let expectedFrame = try #require(dependencies.targetProvider.snapshot?.screenFrame)
        let publishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: publishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == publishID
        }

        #expect(controller.panelIsVisibleForTesting)
        #expect(controller.panelFrameForTesting == expectedFrame)
        #expect(controller.panelIgnoresMouseEventsForTesting)
    }

    @Test
    @MainActor
    func pasteShortcutCompletionKeepsSuccessEnding() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let publishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: publishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == publishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .completed(
                TranscriptPublishFeedbackCompletion(
                    publishID: publishID,
                    outcome: .pasteShortcutSent
                )
            )
        )

        try await eventually {
            controller.endingStyleForTesting == .success
        }
    }

    @Test
    @MainActor
    func clipboardCompletionUsesDowngradedEnding() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let publishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: publishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == publishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .completed(
                TranscriptPublishFeedbackCompletion(
                    publishID: publishID,
                    outcome: .copiedToClipboard
                )
            )
        )

        try await eventually {
            controller.endingStyleForTesting == .downgraded
        }
    }

    @Test
    @MainActor
    func completionForDifferentPublishIDIsIgnored() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let activePublishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: activePublishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == activePublishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .completed(
                TranscriptPublishFeedbackCompletion(
                    publishID: UUID(),
                    outcome: .copiedToClipboard
                )
            )
        )

        try await Task.sleep(for: .milliseconds(80))

        #expect(controller.activePublishIDForTesting == activePublishID)
        #expect(controller.endingStyleForTesting == .success)
    }

    @Test
    @MainActor
    func missingTargetSnapshotSkipsOverlayPresentation() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies(targetSnapshot: nil)
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: UUID(),
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.activePublishIDForTesting == nil)
        #expect(controller.panelIsVisibleForTesting == false)
    }

    @Test
    @MainActor
    func mismatchedFailedDoesNotHideActiveOverlay() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let activePublishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: activePublishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == activePublishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .failed(
                TranscriptPublishFeedbackFailure(
                    publishID: UUID()
                )
            )
        )

        try await Task.sleep(for: .milliseconds(150))

        #expect(controller.activePublishIDForTesting == activePublishID)
        #expect(controller.panelIsVisibleForTesting)
    }

    @Test
    @MainActor
    func mismatchedPublishedOnlyCompletionDoesNotHideActiveOverlay() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let activePublishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: activePublishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == activePublishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .completed(
                TranscriptPublishFeedbackCompletion(
                    publishID: UUID(),
                    outcome: .publishedOnly
                )
            )
        )

        try await Task.sleep(for: .milliseconds(150))

        #expect(controller.activePublishIDForTesting == activePublishID)
        #expect(controller.panelIsVisibleForTesting)
    }

    @Test
    @MainActor
    func rapidPublishedOnlyHideThenRestartKeepsNewOverlayVisibleAfterFadeWindow() async throws {
        let dependencies = makeTranscriptInjectionOverlayDependencies()
        let controller = TranscriptInjectionOverlayController(
            coordinator: dependencies.coordinator,
            targetProvider: dependencies.targetProvider,
            visibleDuration: .seconds(10)
        )
        let firstPublishID = UUID()
        let secondPublishID = UUID()

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: firstPublishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == firstPublishID
        }

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .completed(
                TranscriptPublishFeedbackCompletion(
                    publishID: firstPublishID,
                    outcome: .publishedOnly
                )
            )
        )

        dependencies.coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: secondPublishID,
                    transcript: PublishedTranscript(text: "hello again")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == secondPublishID
        }

        try await Task.sleep(for: .milliseconds(150))

        #expect(controller.activePublishIDForTesting == secondPublishID)
        #expect(controller.panelIsVisibleForTesting)
    }

    @Test
    @MainActor
    func startedWithoutTargetSnapshotClearsPreviouslyVisibleOverlay() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let targetProvider = MutableTranscriptInjectionTargetSnapshotProvider()
        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            sleepClock: ImmediateSleepClock()
        )
        let controller = TranscriptInjectionOverlayController(
            coordinator: coordinator,
            targetProvider: targetProvider,
            visibleDuration: .seconds(10)
        )
        let firstPublishID = UUID()

        coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: firstPublishID,
                    transcript: PublishedTranscript(text: "ni hao")
                )
            )
        )

        try await eventually {
            controller.activePublishIDForTesting == firstPublishID
        }

        targetProvider.snapshot = nil

        coordinator.publishFeedbackNotifier.notify(
            .started(
                TranscriptPublishFeedbackStart(
                    publishID: UUID(),
                    transcript: PublishedTranscript(text: "second")
                )
            )
        )

        try await Task.sleep(for: .milliseconds(150))

        #expect(controller.activePublishIDForTesting == nil)
        #expect(controller.panelIsVisibleForTesting == false)
    }
}

@MainActor
private func makeTranscriptInjectionOverlayDependencies(
    targetSnapshot: TranscriptInjectionTargetSnapshot? = TranscriptInjectionTargetSnapshot(
        processIdentifier: 4242,
        appIdentifier: "com.apple.TextEdit",
        appName: "TextEdit",
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        windowFrame: CGRect(x: 180, y: 160, width: 820, height: 520),
        elementFrame: CGRect(x: 260, y: 260, width: 360, height: 44),
        destinationPoint: CGPoint(x: 440, y: 282)
    )
) -> TranscriptInjectionOverlayTestDependencies {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let targetProvider = MockTranscriptInjectionTargetSnapshotProvider(snapshot: targetSnapshot)
    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        sleepClock: ImmediateSleepClock()
    )

    return TranscriptInjectionOverlayTestDependencies(
        coordinator: coordinator,
        targetProvider: targetProvider,
        targetSnapshot: targetSnapshot
    )
}

@MainActor
private struct TranscriptInjectionOverlayTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let targetProvider: MockTranscriptInjectionTargetSnapshotProvider
    let targetSnapshot: TranscriptInjectionTargetSnapshot?
}

private final class MutableTranscriptInjectionTargetSnapshotProvider: TranscriptInjectionTargetSnapshotProviding, @unchecked Sendable {
    var snapshot: TranscriptInjectionTargetSnapshot? = TranscriptInjectionTargetSnapshot(
        processIdentifier: 4242,
        appIdentifier: "com.apple.TextEdit",
        appName: "TextEdit",
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        windowFrame: CGRect(x: 180, y: 160, width: 820, height: 520),
        elementFrame: CGRect(x: 260, y: 260, width: 360, height: 44),
        destinationPoint: CGPoint(x: 440, y: 282)
    )

    func currentTranscriptInjectionTargetSnapshot() async -> TranscriptInjectionTargetSnapshot? {
        snapshot
    }
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
