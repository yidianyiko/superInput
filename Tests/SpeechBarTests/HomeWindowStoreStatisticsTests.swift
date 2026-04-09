import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain

@Suite("HomeWindowStoreStatistics", .serialized)
struct HomeWindowStoreStatisticsTests {
    @Test
    @MainActor
    func completedSessionDurationReflectsRecordingTimeInsteadOfFinalizeDelay() async throws {
        let dependencies = makeStatisticsDependencies()
        dependencies.client.finalizeDelay = .milliseconds(250)

        dependencies.coordinator.start()
        dependencies.hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            dependencies.coordinator.sessionState == .recording
        }

        dependencies.audio.emit(
            AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0)
        )
        dependencies.client.emit(.final("hello"))

        try await Task.sleep(for: .milliseconds(40))

        dependencies.hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        dependencies.client.emit(.utteranceEnded)

        try await eventually {
            dependencies.store.history.count == 1
        }

        let duration = try #require(dependencies.store.history.first?.durationSeconds)
        #expect(duration >= 0.02)
        #expect(duration < 0.15)
    }

    @Test
    @MainActor
    func secondCompletedSessionUsesCurrentDeliveryOutcome() async throws {
        let dependencies = makeStatisticsDependencies()

        dependencies.coordinator.start()

        try await runCompletedSession(
            transcript: "first",
            dependencies: dependencies
        )

        await dependencies.publisher.setOutcome(.copiedToClipboard)

        try await runCompletedSession(
            transcript: "second",
            dependencies: dependencies
        )

        try await eventually {
            dependencies.store.history.count == 2
        }

        #expect(dependencies.store.history.first?.text == "second")
        #expect(dependencies.store.history.first?.deliveryLabel == "已复制剪贴板")
    }

    @Test
    @MainActor
    func cumulativeStatisticsContinueGrowingAfterRecentHistoryHitsCap() async throws {
        let defaults = makeStatisticsDefaults()
        let seededHistory = (0..<120).map { index in
            HomeWindowStore.TranscriptHistoryItem(
                id: UUID(),
                text: "x",
                createdAt: Date().addingTimeInterval(TimeInterval(-index)),
                characterCount: 1,
                durationSeconds: 1,
                deliveryLabel: "已完成转写"
            )
        }
        defaults.set(try JSONEncoder().encode(seededHistory), forKey: "home.history")

        let dependencies = makeStatisticsDependencies(defaults: defaults)
        dependencies.coordinator.start()

        #expect(dependencies.store.history.count == 120)
        #expect(dependencies.store.totalSessionCount == 120)
        #expect(dependencies.store.totalCharacterCount == 120)
        #expect(dependencies.store.todaySessionCount == 120)

        try await runCompletedSession(
            transcript: "hello",
            dependencies: dependencies
        )

        try await eventually {
            dependencies.store.history.count == 120 && dependencies.store.history.first?.text == "hello"
        }

        let todayUsage = dependencies.store.weeklyUsage.first(where: \.isToday)
        #expect(dependencies.store.totalSessionCount == 121)
        #expect(dependencies.store.totalCharacterCount == 125)
        #expect(dependencies.store.todaySessionCount == 121)
        #expect(todayUsage?.count == 121)
    }
}

@MainActor
private func runCompletedSession(
    transcript: String,
    dependencies: HomeWindowStoreStatisticsDependencies
) async throws {
    dependencies.hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

    try await eventually {
        dependencies.coordinator.sessionState == .recording
    }

    dependencies.audio.emit(
        AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0)
    )
    dependencies.client.emit(.final(transcript))
    dependencies.hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
    dependencies.client.emit(.utteranceEnded)

    try await eventually {
        dependencies.coordinator.sessionState == .idle && dependencies.store.history.first?.text == transcript
    }
}

@MainActor
private func makeStatisticsDependencies(
    defaults: UserDefaults = makeStatisticsDefaults()
) -> HomeWindowStoreStatisticsDependencies {
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
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
    let store = HomeWindowStore(coordinator: coordinator, defaults: defaults)
    return HomeWindowStoreStatisticsDependencies(
        hardware: hardware,
        audio: audio,
        client: client,
        publisher: publisher,
        coordinator: coordinator,
        store: store
    )
}

private func makeStatisticsDefaults() -> UserDefaults {
    let suiteName = "HomeWindowStoreStatisticsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private struct HomeWindowStoreStatisticsDependencies {
    let hardware: MockHardwareEventSource
    let audio: MockAudioInputSource
    let client: MockTranscriptionClient
    let publisher: MockTranscriptPublisher
    let coordinator: VoiceSessionCoordinator
    let store: HomeWindowStore
}

private func eventually(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock().now + timeout
    while ContinuousClock().now < deadline {
        if await MainActor.run(body: condition) {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    Issue.record("Condition was not met before timeout.")
}
