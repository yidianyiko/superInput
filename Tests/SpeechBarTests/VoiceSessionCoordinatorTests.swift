import Foundation
import Testing
@testable import SpeechBarApplication
import MemoryDomain
import SpeechBarDomain

@Suite("VoiceSessionCoordinator", .serialized)
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
    func publishFeedbackNotifierEmitsStartedAndCompletedEventsForPastePath() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        await publisher.setOutcome(.pasteShortcutSent)

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            sleepClock: ImmediateSleepClock()
        )

        let eventTask = Task {
            await collectPublishFeedbackEvents(
                from: coordinator.publishFeedbackNotifier.events,
                count: 2
            )
        }

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
            coordinator.sessionState == .idle
        }

        let events = await eventTask.value
        #expect(events.count == 2)

        guard case .started(let started) = events[0] else {
            Issue.record("Expected started event first.")
            return
        }

        guard case .completed(let completed) = events[1] else {
            Issue.record("Expected completed event second.")
            return
        }

        #expect(started.transcript.text == "ni hao")
        #expect(completed.outcome == .pasteShortcutSent)
        #expect(started.publishID == completed.publishID)
    }

    @Test
    @MainActor
    func publishFeedbackNotifierEmitsFailedEventWhenPublisherThrows() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        await publisher.setError(MockFailure.publish)

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            sleepClock: ImmediateSleepClock()
        )

        let eventTask = Task {
            await collectPublishFeedbackEvents(
                from: coordinator.publishFeedbackNotifier.events,
                count: 2
            )
        }

        coordinator.start()

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        audio.emit(AudioChunk(data: Data([0x01, 0x02]), format: .deepgramLinear16, sequenceNumber: 0))
        client.emit(.final("ni hao"))

        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually {
            coordinator.sessionState == .idle
        }

        let events = await eventTask.value
        #expect(events.count == 2)

        guard case .started(let started) = events[0] else {
            Issue.record("Expected started event first.")
            return
        }

        guard case .failed(let failed) = events[1] else {
            Issue.record("Expected failed event second.")
            return
        }

        #expect(started.publishID == failed.publishID)
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
                return message == "Microphone permission is required."
            }
            return false
        }
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
                return message == "No speech was detected. Try again."
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
    func dismissSelectedStopsActiveSession() async throws {
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
        hardware.send(HardwareEvent(source: .usbHID, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording
        }

        hardware.send(HardwareEvent(source: .usbHID, kind: .dismissSelected))
        client.emit(.utteranceEnded)

        try await eventually {
            if case .failed(let message) = coordinator.sessionState {
                return message == "No speech was detected. Try again."
            }
            return false
        }

        #expect(client.finalizeCallCount == 1)
    }

    @Test
    @MainActor
    func switchBoardEventsTriggerWindowSwitching() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let windowSwitcher = MockWindowSwitcher()

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            windowSwitcher: windowSwitcher,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .usbHID, kind: .switchBoardNext))
        hardware.send(HardwareEvent(source: .usbHID, kind: .switchBoardPrevious))

        try await eventuallyAsync {
            await windowSwitcher.snapshot() == [.next, .previous]
        }
    }

    @Test
    @MainActor
    func boardPrimaryAndSecondaryPressesTriggerReturnKeyHandler() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let returnKeyCounter = MockReturnKeyPressCounter()

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            returnKeyHandler: {
                returnKeyCounter.press()
            },
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .usbHID, kind: .pressPrimary))
        hardware.send(HardwareEvent(source: .usbHID, kind: .pressSecondary))

        try await eventually {
            returnKeyCounter.snapshot() == 2
        }
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

    @Test
    @MainActor
    func replyModeAllowsReadyToSendRewrite() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let postProcessor = MockTranscriptPostProcessor()
        let rawTranscript = "你先看一下这个方案要是可以的话回我一下"
        let polishedTranscript = "收到，你先看一下方案，如果可以的话回我一下。"
        postProcessor.polishedText = polishedTranscript
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "创业者",
                memoryProfile: "偏好：像本人一样回消息",
                terminologyGlossary: [],
                polishMode: .reply
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
        #expect(postProcessor.receivedContexts.last?.polishMode == .reply)
    }

    @Test
    @MainActor
    func successfulPublishRecordsObservedInputEvent() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let recorder = MockMemoryRecorder()
        let snapshotProvider = MockFocusedInputSnapshotProvider()

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            focusedSnapshotProvider: snapshotProvider,
            memoryRecorder: recorder,
            sleepClock: ImmediateSleepClock()
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
        try await eventually { coordinator.sessionState == .recording }
        client.emit(.final("ni hao"))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventuallyAsync { await recorder.recordedEventCount == 1 }
    }

    @Test
    @MainActor
    func highFrequencyAudioLevelsAreCoalescedToReduceUIRefreshPressure() async throws {
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

        let startedAt = Date()
        for index in 0..<12 {
            audio.emit(
                level: AudioLevelSample(
                    level: Double(index + 1) / 12.0,
                    peak: Double(index + 1) / 12.0,
                    capturedAt: startedAt.addingTimeInterval(Double(index) * 0.01)
                )
            )
        }

        try await eventually {
            !coordinator.audioLevelWindow.isEmpty
        }

        #expect(coordinator.audioLevelWindow.count == 3)
    }

    @Test
    @MainActor
    func spacedAudioLevelsStillPopulateTheWaveformWindow() async throws {
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

        let startedAt = Date()
        for index in 0..<3 {
            audio.emit(
                level: AudioLevelSample(
                    level: Double(index + 1) / 3.0,
                    peak: Double(index + 1) / 3.0,
                    capturedAt: startedAt.addingTimeInterval(Double(index) * 0.08)
                )
            )
        }

        try await eventually {
            coordinator.audioLevelWindow.count == 3
        }
    }

    @Test
    @MainActor
    func optedOutFieldLabelsClassifyRecordedEventAsOptOut() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let recorder = MockMemoryRecorder()
        let snapshotProvider = MockFocusedInputSnapshotProvider(
            snapshot: FocusedInputSnapshot(
                appIdentifier: "com.apple.TextEdit",
                appName: "TextEdit",
                windowTitle: "Untitled",
                pageTitle: nil,
                fieldRole: "AXTextArea",
                fieldLabel: "Body",
                isEditable: true,
                isSecure: false
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            focusedSnapshotProvider: snapshotProvider,
            memoryRecorder: recorder,
            sleepClock: ImmediateSleepClock(),
            memoryOptedOutFieldLabels: { ["body"] }
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
        try await eventually { coordinator.sessionState == .recording }
        client.emit(.final("ni hao"))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventuallyAsync { await recorder.recordedEventCount == 1 }
        let event = await recorder.snapshot().last
        #expect(event?.sensitivityClass == .optOut)
    }

    @Test
    @MainActor
    func recallAddsKeywordsToTranscriptionConfiguration() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let retriever = MockMemoryRetriever(
            bundle: RecallBundle(
                vocabularyHints: ["OpenAI API", "Coze Space"],
                correctionHints: ["扣子空间->Coze Space"],
                styleHints: [],
                sceneHints: [],
                diagnosticSummary: "test"
            )
        )
        let snapshotProvider = MockFocusedInputSnapshotProvider()

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            focusedSnapshotProvider: snapshotProvider,
            memoryRetriever: retriever,
            sleepClock: ImmediateSleepClock(),
            memoryRecallEnabled: { true }
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            client.lastConfiguration?.keywords.contains("OpenAI API") == true
        }
    }

    @Test
    @MainActor
    func recallAugmentsPolishContextMemoryProfile() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let postProcessor = MockTranscriptPostProcessor()
        let retriever = MockMemoryRetriever(
            bundle: RecallBundle(
                vocabularyHints: [],
                correctionHints: [],
                styleHints: ["tone=polite", "brevity=short"],
                sceneHints: ["app=com.apple.mail"],
                diagnosticSummary: "test"
            )
        )
        let snapshotProvider = MockFocusedInputSnapshotProvider()

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            focusedSnapshotProvider: snapshotProvider,
            userProfileProvider: MockUserProfileContextProvider(),
            transcriptPostProcessor: postProcessor,
            memoryRetriever: retriever,
            sleepClock: ImmediateSleepClock(),
            memoryRecallEnabled: { true }
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))
        try await eventually { coordinator.sessionState == .recording }
        client.emit(.final("hello world this needs polish"))
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkReleased))
        client.emit(.utteranceEnded)

        try await eventually { !postProcessor.receivedContexts.isEmpty }
        #expect(postProcessor.receivedContexts.last?.memoryProfile.contains("tone=polite") == true)
    }

    @Test
    @MainActor
    func activeInputHintsSurfaceProfileGlossaryAndRecallSignals() async throws {
        let hardware = MockHardwareEventSource()
        let audio = MockAudioInputSource()
        let client = MockTranscriptionClient()
        let credentials = MockCredentialProvider(storedAPIKey: "test-key")
        let publisher = MockTranscriptPublisher()
        let retriever = MockMemoryRetriever(
            bundle: RecallBundle(
                vocabularyHints: ["Demo Day"],
                correctionHints: [],
                styleHints: ["brevity=short"],
                sceneHints: [],
                diagnosticSummary: "test"
            )
        )
        let snapshotProvider = MockFocusedInputSnapshotProvider()
        let userProfileProvider = MockUserProfileContextProvider(
            context: UserProfileContext(
                profession: "AI 创业者",
                memoryProfile: "偏好：结论先行\n偏好：自然一点，不要太正式",
                terminologyGlossary: [
                    TerminologyEntry(term: "Redheak", isEnabled: true)
                ],
                polishMode: .reply
            )
        )

        let coordinator = VoiceSessionCoordinator(
            hardwareSource: hardware,
            audioInputSource: audio,
            transcriptionClient: client,
            credentialProvider: credentials,
            transcriptPublisher: publisher,
            focusedSnapshotProvider: snapshotProvider,
            userProfileProvider: userProfileProvider,
            memoryRetriever: retriever,
            sleepClock: ImmediateSleepClock(),
            memoryRecallEnabled: { true }
        )

        coordinator.start()
        hardware.send(HardwareEvent(source: .onScreenButton, kind: .pushToTalkPressed))

        try await eventually {
            coordinator.sessionState == .recording && !coordinator.activeInputHints.isEmpty
        }

        #expect(coordinator.activeInputHints.contains("风格·结论先行"))
        #expect(coordinator.activeInputHints.contains("术语·Redheak"))
        #expect(coordinator.activeInputHints.contains("术语·Demo Day"))
        #expect(coordinator.activeInputHints.contains("风格·简短"))
    }
}

private enum TestFailure: Error {
    case timeout
}

private enum MockFailure: Error {
    case publish
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

@MainActor
private func eventuallyAsync(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(20),
    _ predicate: @escaping () async -> Bool
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

private func collectPublishFeedbackEvents(
    from stream: AsyncStream<TranscriptPublishFeedbackEvent>,
    count: Int
) async -> [TranscriptPublishFeedbackEvent] {
    var iterator = stream.makeAsyncIterator()
    var events: [TranscriptPublishFeedbackEvent] = []

    while events.count < count, let event = await iterator.next() {
        events.append(event)
    }

    return events
}
