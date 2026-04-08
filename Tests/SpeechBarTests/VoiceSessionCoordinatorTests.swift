import Foundation
import Testing
@testable import SpeechBarApplication
import SpeechBarDomain

@Suite("VoiceSessionCoordinator")
struct VoiceSessionCoordinatorTests {
    @Test
    @MainActor
    func successfulPushToTalkPublishesFinalTranscript() async throws {
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

        coordinator.start()

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        audio.emit(AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0))

        client.emit(.interim("ni hao"))
        client.emit(.final("ni hao"))

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            coordinator.sessionState == .idle && coordinator.finalTranscript == "ni hao"
        }

        let published = await publisher.snapshot()
        #expect(published.map(\.text) == ["ni hao"])
        #expect(client.finalizeCallCount == 1)
        #expect(!client.sentChunks.isEmpty)
    }

    @Test
    @MainActor
    func permissionDeniedMovesCoordinatorToFailedState() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        audio.permissionStatus = .denied
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

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            if case .failed(let message) = coordinator.sessionState {
                return message == "需要授予麦克风权限。"
            }
            return false
        }
    }

    @Test
    @MainActor
    func startsCaptureBeforeLoadingCredentials() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let publisher = MockTranscriptPublisher()
        let credentials = StartCaptureOrderCredentialProvider(audio: audio)

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        #expect(credentials.sawStartedCaptureBeforeLoad)
        #expect(audio.startCallCount == 1)
    }

    @Test
    @MainActor
    func networkErrorMovesCoordinatorToFailedState() async throws {
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

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        client.emit(.error("Network dropped"))

        try await eventually {
            if case .failed(let message) = coordinator.sessionState {
                return message == "Network dropped"
            }
            return false
        }
    }

    @Test
    @MainActor
    func noSpeechAfterFinalizeFailsCleanly() async throws {
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

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            if case .failed(let message) = coordinator.sessionState {
                return message == "没有检测到语音，请重试。"
            }
            return false
        }
    }

    @Test
    @MainActor
    func repeatedPressWhileRecordingDoesNotStartSecondSession() async throws {
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

        coordinator.start()

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
        try await eventually {
            coordinator.sessionState == .recording
        }

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
        try await Task.sleep(for: .milliseconds(100))

        #expect(client.connectCallCount == 1)
    }

    @Test
    @MainActor
    func enabledGlossaryTermsAreInjectedIntoConfigurationKeywords() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "AI 创业者",
                memoryProfile: "",
                terminologyGlossary: [
                    TerminologyEntry(term: "OpenAI", isEnabled: true),
                    TerminologyEntry(term: "Deepgram", isEnabled: true),
                    TerminologyEntry(term: "无效术语", isEnabled: false)
                ],
                polishMode: .off
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            userProfileProvider: userProfileProvider,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        #expect(client.lastConfiguration?.keywords == ["OpenAI", "Deepgram"])
    }

    @Test
    @MainActor
    func glossaryMasterSwitchDisablesKeywordInjection() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "AI 创业者",
                memoryProfile: "",
                terminologyGlossary: [
                    TerminologyEntry(term: "OpenAI", isEnabled: true),
                    TerminologyEntry(term: "Deepgram", isEnabled: true)
                ],
                isTerminologyGlossaryEnabled: false,
                polishMode: .off
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            userProfileProvider: userProfileProvider,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        #expect(client.lastConfiguration?.keywords == [])
    }

    @Test
    @MainActor
    func shortTranscriptSkipsPolishRequest() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let postProcessor = MockTranscriptPostProcessor()
        postProcessor.polishedText = "你好，今天见。"
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "创业者",
                memoryProfile: "",
                terminologyGlossary: [],
                polishMode: .light,
                skipShortPolish: true,
                shortPolishCharacterThreshold: 8
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            userProfileProvider: userProfileProvider,
            transcriptPostProcessor: postProcessor,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        audio.emit(AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0))

        client.emit(.final("你好啊"))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            coordinator.sessionState == .idle && coordinator.finalTranscript == "你好啊"
        }

        let published = await publisher.snapshot()
        #expect(published.map(\.text) == ["你好啊"])
        #expect(postProcessor.receivedTranscripts.isEmpty)
        #expect(coordinator.lastPolishFallbackReason == nil)
    }

    @Test
    @MainActor
    func polishFailureFallsBackToRawTranscript() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let postProcessor = MockTranscriptPostProcessor()
        postProcessor.polishedText = ""
        postProcessor.error = NSError(domain: "test", code: 1)
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "AI 创业者",
                memoryProfile: "保留英文术语",
                terminologyGlossary: [],
                polishMode: .light
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            userProfileProvider: userProfileProvider,
            transcriptPostProcessor: postProcessor,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        audio.emit(AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0))

        client.emit(.final("hello world"))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            coordinator.sessionState == .idle && coordinator.finalTranscript == "hello world"
        }

        let published = await publisher.snapshot()
        #expect(published.map(\.text) == ["hello world"])
        #expect(coordinator.lastPolishFallbackReason != nil)
    }

    @Test
    @MainActor
    func chatModeAllowsCondensedRewriteWithinRelaxedThresholds() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let postProcessor = MockTranscriptPostProcessor()
        let rawTranscript = "那个就是我觉得这个方案的话要不我们今天先别发然后明天再看一下"
        let polishedTranscript = "这个方案先别发，等明天再决定。"
        postProcessor.polishedText = polishedTranscript
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "创业者",
                memoryProfile: "适合直接发给同事",
                terminologyGlossary: [],
                polishMode: .chat
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            userProfileProvider: userProfileProvider,
            transcriptPostProcessor: postProcessor,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        audio.emit(AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0))

        client.emit(.final(rawTranscript))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            coordinator.sessionState == .idle && coordinator.finalTranscript == polishedTranscript
        }

        let published = await publisher.snapshot()
        #expect(published.map(\.text) == [polishedTranscript])
        #expect(coordinator.lastPolishFallbackReason == nil)
    }
}

private enum TestFailure: Error {
    case timeout
}

private final class StartCaptureOrderCredentialProvider: CredentialProvider, @unchecked Sendable {
    private let audio: MockAudioInputSource
    private(set) var sawStartedCaptureBeforeLoad = false

    init(audio: MockAudioInputSource) {
        self.audio = audio
    }

    func credentialStatus() -> CredentialStatus {
        .available
    }

    func loadAPIKey() throws -> String {
        sawStartedCaptureBeforeLoad = audio.startCallCount > 0
        return "test-key"
    }

    func save(apiKey: String) throws {}

    func deleteAPIKey() throws {}
}

private func eventually(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(20),
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if await predicate() {
            return
        }
        try await clock.sleep(for: pollInterval)
    }

    throw TestFailure.timeout
}
