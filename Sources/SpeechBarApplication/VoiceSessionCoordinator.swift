import Combine
import CoreGraphics
import Foundation
import MemoryDomain
import SpeechBarDomain

private func performanceLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Perf] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

@MainActor
public final class VoiceSessionCoordinator: ObservableObject {
    private static let audioLevelUIUpdateMinimumInterval: TimeInterval = 0.05

    @Published public private(set) var sessionState: SpeechSessionState = .idle
    @Published public private(set) var rawFinalTranscript = ""
    @Published public private(set) var interimTranscript = ""
    @Published public private(set) var finalTranscript = ""
    @Published public private(set) var statusMessage = "Ready"
    @Published public private(set) var credentialStatus: CredentialStatus = .missing
    @Published public private(set) var isPushToTalkActive = false
    @Published public private(set) var lastCompletedTranscript: PublishedTranscript?
    @Published public private(set) var lastDeliveryOutcome: TranscriptDeliveryOutcome?
    @Published public private(set) var lastCompletedSessionDuration: TimeInterval?
    @Published public private(set) var lastPolishFallbackReason: String?
    @Published public private(set) var overlayPhase: RecordingOverlayPhase = .hidden
    @Published public private(set) var overlaySubtitle = ""
    @Published public private(set) var audioLevelWindow: [AudioLevelSample] = []
    @Published public private(set) var activeInputHints: [String] = []

    public let publishFeedbackNotifier: TranscriptPublishFeedbackNotifier

    private let hardwareSource: any HardwareEventSource
    private let audioInputSource: any AudioInputSource
    private let transcriptionClient: any TranscriptionClient
    private let credentialProvider: any CredentialProvider
    private let transcriptPublisher: any TranscriptPublisher
    private let windowSwitcher: (any WindowSwitching)?
    private let returnKeyHandler: @Sendable () -> Void
    private let transcriptTargetCapturer: (any TranscriptTargetCapturing)?
    private let focusedSnapshotProvider: (any FocusedInputSnapshotProviding)?
    private let userProfileProvider: (any UserProfileContextProviding)?
    private let transcriptPostProcessor: (any TranscriptPostProcessor)?
    private let memoryRecorder: (any MemoryEventRecording)?
    private let memoryRetriever: (any MemoryRetriever)?
    private let diagnostics: DiagnosticsCoordinator?
    private let baseConfiguration: LiveTranscriptionConfiguration
    private let sleepClock: any SleepClock
    private let memoryCaptureEnabled: @Sendable () async -> Bool
    private let memoryRecallEnabled: @Sendable () async -> Bool
    private let memoryOptedOutApps: @Sendable () async -> Set<String>
    private let memoryOptedOutFieldLabels: @Sendable () async -> Set<String>

    private var hardwareTask: Task<Void, Never>?
    private var transcriptionEventTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var finalizeTimeoutTask: Task<Void, Never>?

    private var hasStarted = false
    private var activeSessionID: UUID?
    private var activeSessionStartedAt: Date?
    private var activeFinalizeStartedAt: Date?
    private var activePublishFeedbackID: UUID?
    private var shouldFinalizeWhenReady = false
    private var isCompletingActiveSession = false
    private var finalSegments: [String] = []
    private var activeRecallBundle: RecallBundle?
    private var lastAudioLevelWindowUpdateAt: Date?

    public init(
        hardwareSource: any HardwareEventSource,
        audioInputSource: any AudioInputSource,
        transcriptionClient: any TranscriptionClient,
        credentialProvider: any CredentialProvider,
        transcriptPublisher: any TranscriptPublisher,
        publishFeedbackNotifier: TranscriptPublishFeedbackNotifier = TranscriptPublishFeedbackNotifier(),
        windowSwitcher: (any WindowSwitching)? = nil,
        returnKeyHandler: @escaping @Sendable () -> Void = {
            guard let source = CGEventSource(stateID: .combinedSessionState)
                ?? CGEventSource(stateID: .hidSystemState)
            else {
                return
            }

            let returnKeyCode: CGKeyCode = 36
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        },
        transcriptTargetCapturer: (any TranscriptTargetCapturing)? = nil,
        focusedSnapshotProvider: (any FocusedInputSnapshotProviding)? = nil,
        userProfileProvider: (any UserProfileContextProviding)? = nil,
        transcriptPostProcessor: (any TranscriptPostProcessor)? = nil,
        memoryRecorder: (any MemoryEventRecording)? = nil,
        memoryRetriever: (any MemoryRetriever)? = nil,
        diagnostics: DiagnosticsCoordinator? = nil,
        configuration: LiveTranscriptionConfiguration = LiveTranscriptionConfiguration(),
        sleepClock: any SleepClock = ContinuousSleepClock(),
        memoryCaptureEnabled: @escaping @Sendable () async -> Bool = { true },
        memoryRecallEnabled: @escaping @Sendable () async -> Bool = { false },
        memoryOptedOutApps: @escaping @Sendable () async -> Set<String> = { [] },
        memoryOptedOutFieldLabels: @escaping @Sendable () async -> Set<String> = { [] }
    ) {
        self.hardwareSource = hardwareSource
        self.audioInputSource = audioInputSource
        self.transcriptionClient = transcriptionClient
        self.credentialProvider = credentialProvider
        self.transcriptPublisher = transcriptPublisher
        self.publishFeedbackNotifier = publishFeedbackNotifier
        self.windowSwitcher = windowSwitcher
        self.returnKeyHandler = returnKeyHandler
        self.transcriptTargetCapturer = transcriptTargetCapturer
        self.focusedSnapshotProvider = focusedSnapshotProvider
        self.userProfileProvider = userProfileProvider
        self.transcriptPostProcessor = transcriptPostProcessor
        self.memoryRecorder = memoryRecorder
        self.memoryRetriever = memoryRetriever
        self.diagnostics = diagnostics
        self.baseConfiguration = configuration
        self.sleepClock = sleepClock
        self.memoryCaptureEnabled = memoryCaptureEnabled
        self.memoryRecallEnabled = memoryRecallEnabled
        self.memoryOptedOutApps = memoryOptedOutApps
        self.memoryOptedOutFieldLabels = memoryOptedOutFieldLabels
        self.credentialStatus = credentialProvider.credentialStatus()
    }

    deinit {
        hardwareTask?.cancel()
        transcriptionEventTask?.cancel()
        audioTask?.cancel()
        audioLevelTask?.cancel()
        finalizeTimeoutTask?.cancel()
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshCredentialStatus()

        if hardwareTask == nil {
            hardwareTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.hardwareSource.events {
                    await self.handleHardwareEvent(event)
                }
            }
        }

        if transcriptionEventTask == nil {
            transcriptionEventTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.transcriptionClient.events {
                    await self.handleTranscriptEvent(event)
                }
            }
        }

        if audioLevelTask == nil {
            audioLevelTask = Task { [weak self] in
                guard let self else { return }
                for await level in self.audioInputSource.audioLevels {
                    self.handleAudioLevel(level)
                }
            }
        }
    }

    public func refreshCredentialStatus() {
        credentialStatus = credentialProvider.credentialStatus()
    }

    public func saveAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sessionState = .failed("Transcription API key cannot be empty.")
            statusMessage = "Enter a valid transcription API key."
            return
        }

        do {
            try credentialProvider.save(apiKey: trimmed)
            refreshCredentialStatus()
            statusMessage = "Transcription API key saved locally."
            if case .failed = sessionState {
                sessionState = .idle
            }
        } catch {
            sessionState = .failed("Could not save the transcription API key.")
            statusMessage = error.localizedDescription
        }
    }

    public func clearAPIKey() {
        do {
            try credentialProvider.deleteAPIKey()
            refreshCredentialStatus()
            statusMessage = "Transcription API key removed from local storage."
            sessionState = .idle
        } catch {
            sessionState = .failed("Could not remove the transcription API key.")
            statusMessage = error.localizedDescription
        }
    }

    public func finalizeCaptureFromOverlay() {
        Task { [weak self] in
            await self?.endVoiceCapture()
        }
    }

    public func cancelCaptureFromOverlay() {
        Task { [weak self] in
            await self?.cancelActiveSession()
        }
    }

    private func handleHardwareEvent(_ event: HardwareEvent) async {
        switch mapAppIntent(from: event) {
        case .startVoiceCapture:
            await beginVoiceCapture()
        case .stopVoiceCapture:
            await endVoiceCapture()
        case .switchWindow(let direction, _):
            await switchWindow(direction)
        case .pressReturnKey:
            returnKeyHandler()
        }
    }

    private func mapAppIntent(from event: HardwareEvent) -> AppIntent {
        switch event.kind {
        case .pushToTalkPressed:
            return .startVoiceCapture(source: event.source)
        case .pushToTalkReleased:
            return .stopVoiceCapture(source: event.source)
        case .pressPrimary, .pressSecondary:
            return .pressReturnKey(source: event.source)
        case .rotaryClockwise, .switchBoardNext:
            return .switchWindow(direction: .next, source: event.source)
        case .rotaryCounterClockwise, .switchBoardPrevious:
            return .switchWindow(direction: .previous, source: event.source)
        case .dismissSelected:
            return .stopVoiceCapture(source: event.source)
        }
    }

    private func switchWindow(_ direction: WindowSwitchDirection) async {
        guard let windowSwitcher else { return }

        let outcome = await windowSwitcher.switchWindow(direction: direction)

        switch outcome {
        case .switchedWindow:
            statusMessage = direction == .next
                ? "Switched to the next window."
                : "Switched to the previous window."
        case .switchedApplication:
            statusMessage = direction == .next
                ? "Switched to the next app."
                : "Switched to the previous app."
        case .permissionDenied:
            statusMessage = "Accessibility permission is required for window switching."
        case .unavailable:
            statusMessage = "No additional window was available to switch."
        }
    }

    private func beginVoiceCapture() async {
        switch sessionState {
        case .requestingPermission, .connecting, .recording, .finalizing:
            return
        case .idle, .failed:
            break
        }

        await transcriptTargetCapturer?.captureCurrentTarget()

        let sessionID = UUID()
        activeSessionID = sessionID
        shouldFinalizeWhenReady = false
        isCompletingActiveSession = false
        finalSegments = []
        rawFinalTranscript = ""
        interimTranscript = ""
        finalTranscript = ""
        lastPolishFallbackReason = nil
        activeRecallBundle = nil
        activeInputHints = []
        statusMessage = "Preparing microphone..."
        isPushToTalkActive = true
        sessionState = .requestingPermission
        overlayPhase = .recording
        overlaySubtitle = "Listening"
        audioLevelWindow = []
        lastAudioLevelWindowUpdateAt = nil

        let apiKey: String
        do {
            apiKey = try credentialProvider.loadAPIKey()
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            await failActiveSession(
                message: message.isEmpty ? "Transcription service is not ready." : message
            )
            return
        }

        let permission = await audioInputSource.requestRecordPermission()
        guard isCurrentSession(sessionID) else { return }

        guard permission == .granted else {
            await failActiveSession(message: "Microphone permission is required.")
            return
        }

        sessionState = .connecting
        statusMessage = "Connecting to transcription service..."

        let context = await currentUserProfileContext()
        activeRecallBundle = await currentRecallBundle()
        activeInputHints = makeActiveInputHints(context: context, recall: activeRecallBundle)
        let sessionConfiguration = makeSessionConfiguration(context: context, recall: activeRecallBundle)

        do {
            try await transcriptionClient.connect(apiKey: apiKey, configuration: sessionConfiguration)
        } catch {
            await failActiveSession(message: "Could not connect to the transcription service.")
            return
        }

        guard isCurrentSession(sessionID) else {
            await transcriptionClient.close()
            return
        }

        let audioStream: AsyncThrowingStream<AudioChunk, Error>
        do {
            audioStream = try await audioInputSource.startCapture()
        } catch {
            await failActiveSession(message: "Could not start audio capture.")
            return
        }

        guard isCurrentSession(sessionID) else {
            await audioInputSource.stopCapture()
            await transcriptionClient.close()
            return
        }

        audioTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in audioStream {
                    try await self.transcriptionClient.send(audioChunk: chunk)
                }
            } catch is CancellationError {
                return
            } catch {
                await self.failActiveSession(message: "Uploading audio to the transcription service failed.")
            }
        }

        activeSessionStartedAt = Date()
        sessionState = .recording
        statusMessage = "Listening..."
        overlayPhase = .recording
        overlaySubtitle = "Listening"

        if shouldFinalizeWhenReady {
            await finalizeActiveSession()
        }
    }

    private func endVoiceCapture() async {
        isPushToTalkActive = false

        switch sessionState {
        case .requestingPermission, .connecting:
            shouldFinalizeWhenReady = true
            statusMessage = "Stopping..."
        case .recording:
            await finalizeActiveSession()
        case .idle, .finalizing, .failed:
            break
        }
    }

    private func finalizeActiveSession() async {
        guard activeSessionID != nil else { return }
        guard sessionState != .finalizing else { return }

        sessionState = .finalizing
        statusMessage = "Finalizing transcript..."
        shouldFinalizeWhenReady = false
        activeFinalizeStartedAt = Date()
        overlayPhase = .finalizing
        overlaySubtitle = "Transcribing"
        if let activeSessionStartedAt {
            performanceLog(
                "finalize started, captureDuration=\(String(format: "%.3f", Date().timeIntervalSince(activeSessionStartedAt)))s"
            )
        } else {
            performanceLog("finalize started")
        }

        await audioInputSource.stopCapture()

        do {
            try await transcriptionClient.finalize()
        } catch {
            await failActiveSession(message: "Could not finalize the transcription request.")
            return
        }

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleepClock.sleep(for: .seconds(2))
            } catch {
                return
            }
            await self.completeActiveSessionIfPossible()
        }
    }

    private func handleTranscriptEvent(_ event: TranscriptEvent) async {
        guard activeSessionID != nil || event == .closed else { return }

        switch event {
        case .opened:
            if sessionState == .connecting {
                statusMessage = "Transcription connection open."
            }

        case .speechStarted:
            if sessionState == .recording || sessionState == .finalizing {
                statusMessage = "Speech detected."
            }

        case .interim(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            interimTranscript = text
            if sessionState == .recording {
                statusMessage = "Transcribing live..."
            }

        case .final(let text):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            finalSegments.append(cleaned)
            rawFinalTranscript = finalSegments.joined(separator: " ")
            finalTranscript = rawFinalTranscript
            interimTranscript = ""
            statusMessage = "Transcript updated."

        case .utteranceEnded:
            if sessionState == .finalizing {
                await completeActiveSessionIfPossible()
            }

        case .metadata:
            break

        case .error(let message):
            await failActiveSession(message: message)

        case .closed:
            if sessionState == .finalizing {
                await completeActiveSessionIfPossible()
            }
        }
    }

    private func completeActiveSessionIfPossible() async {
        guard activeSessionID != nil else { return }
        guard !isCompletingActiveSession else { return }
        isCompletingActiveSession = true

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil

        let transcript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty {
            await failActiveSession(message: "No speech was detected. Try again.")
            return
        }

        let context = await currentUserProfileContext()
        let polishContext = makePolishContext(base: context, recall: activeRecallBundle)
        let polishedTranscript: String
        if shouldAttemptPolish(transcript: transcript, context: polishContext) {
            overlayPhase = .polishing
            overlaySubtitle = "Polishing"
            if let activeFinalizeStartedAt {
                performanceLog(
                    "transcription finished, rawChars=\(transcript.count), transcriptionLatency=\(String(format: "%.3f", Date().timeIntervalSince(activeFinalizeStartedAt)))s"
                )
            }
            polishedTranscript = await polishTranscriptIfNeeded(transcript, context: polishContext)
        } else {
            if let activeFinalizeStartedAt {
                performanceLog(
                    "transcription finished, rawChars=\(transcript.count), transcriptionLatency=\(String(format: "%.3f", Date().timeIntervalSince(activeFinalizeStartedAt)))s, polishSkipped=true"
                )
            }
            lastPolishFallbackReason = nil
            polishedTranscript = transcript
        }
        finalTranscript = polishedTranscript

        let completedAt = Date()
        let publishedTranscript = PublishedTranscript(text: polishedTranscript, createdAt: completedAt)
        let completedDuration = activeSessionStartedAt.map { startedAt in
            let endedAt = activeFinalizeStartedAt ?? completedAt
            return max(0, endedAt.timeIntervalSince(startedAt))
        }
        let publishFeedbackID = UUID()
        activePublishFeedbackID = publishFeedbackID
        let deliveryOutcome: TranscriptDeliveryOutcome
        do {
            overlayPhase = .publishing
            overlaySubtitle = "Pasting"
            publishFeedbackNotifier.notify(
                .started(
                    TranscriptPublishFeedbackStart(
                        publishID: publishFeedbackID,
                        transcript: publishedTranscript
                    )
                )
            )
            let publishStartedAt = Date()
            deliveryOutcome = try await transcriptPublisher.publish(publishedTranscript)
            publishFeedbackNotifier.notify(
                .completed(
                    TranscriptPublishFeedbackCompletion(
                        publishID: publishFeedbackID,
                        outcome: deliveryOutcome
                    )
                )
            )
            activePublishFeedbackID = nil
            performanceLog(
                "publish finished, publishLatency=\(String(format: "%.3f", Date().timeIntervalSince(publishStartedAt)))s"
            )
        } catch {
            if let activePublishFeedbackID {
                publishFeedbackNotifier.notify(
                    .failed(
                        TranscriptPublishFeedbackFailure(publishID: activePublishFeedbackID)
                    )
                )
            }
            self.activePublishFeedbackID = nil
            await teardownActiveSession()
            sessionState = .idle
            overlayPhase = .hidden
            overlaySubtitle = ""
            statusMessage = error.localizedDescription.isEmpty
                ? "Transcript ready, but it could not be inserted into the active app."
                : error.localizedDescription
            return
        }

        lastDeliveryOutcome = deliveryOutcome
        lastCompletedSessionDuration = completedDuration
        lastCompletedTranscript = publishedTranscript
        if let activeFinalizeStartedAt {
            performanceLog(
                "session finished, endToEndFinalizeLatency=\(String(format: "%.3f", Date().timeIntervalSince(activeFinalizeStartedAt)))s"
            )
        }
        await recordMemoryEventIfNeeded(
            transcript: transcript,
            polishedTranscript: polishedTranscript,
            completedAt: completedAt,
            completedDuration: completedDuration,
            deliveryOutcome: deliveryOutcome
        )
        await teardownActiveSession()
        sessionState = .idle
        overlayPhase = .hidden
        overlaySubtitle = ""
        switch deliveryOutcome {
        case .insertedIntoFocusedApp:
            statusMessage = "Transcript inserted into the focused app."
        case .typedIntoFocusedApp:
            statusMessage = "Transcript typed into the focused app."
        case .pasteShortcutSent:
            statusMessage = "Transcript recognized. Paste was sent and the text is also in your clipboard. If it did not appear, press Command+V."
        case .copiedToClipboard:
            statusMessage = "Transcript recognized and copied to your clipboard. Click the chat box and press Command+V."
        case .publishedOnly:
            statusMessage = "Transcript recognized."
        }
    }

    private func failActiveSession(message: String) async {
        await teardownActiveSession()
        sessionState = .failed(message)
        statusMessage = message
        overlayPhase = .failed
        overlaySubtitle = message
        audioLevelWindow = []
        lastAudioLevelWindowUpdateAt = nil
        activeInputHints = []
    }

    private func teardownActiveSession() async {
        audioTask?.cancel()
        audioTask = nil

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil

        shouldFinalizeWhenReady = false
        isCompletingActiveSession = false
        isPushToTalkActive = false
        activeSessionID = nil
        activeSessionStartedAt = nil
        activeFinalizeStartedAt = nil
        activePublishFeedbackID = nil
        activeRecallBundle = nil
        audioLevelWindow = []
        lastAudioLevelWindowUpdateAt = nil

        await audioInputSource.stopCapture()
        await transcriptionClient.close()
        await transcriptTargetCapturer?.clearCapturedTarget()
    }

    private func cancelActiveSession() async {
        guard activeSessionID != nil else { return }
        await teardownActiveSession()
        finalSegments = []
        rawFinalTranscript = ""
        interimTranscript = ""
        finalTranscript = ""
        lastPolishFallbackReason = nil
        activeInputHints = []
        sessionState = .idle
        overlayPhase = .hidden
        overlaySubtitle = ""
        statusMessage = "Recording canceled."
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    private func handleAudioLevel(_ sample: AudioLevelSample) {
        guard activeSessionID != nil else { return }
        guard overlayPhase == .recording else { return }
        if let lastAudioLevelWindowUpdateAt,
           sample.capturedAt.timeIntervalSince(lastAudioLevelWindowUpdateAt) < Self.audioLevelUIUpdateMinimumInterval {
            return
        }

        audioLevelWindow.append(sample)
        if audioLevelWindow.count > 24 {
            audioLevelWindow.removeFirst(audioLevelWindow.count - 24)
        }
        lastAudioLevelWindowUpdateAt = sample.capturedAt
    }

    private func currentUserProfileContext() async -> UserProfileContext {
        await userProfileProvider?.currentContext() ?? UserProfileContext()
    }

    private func makeSessionConfiguration(
        context: UserProfileContext,
        recall: RecallBundle?
    ) -> LiveTranscriptionConfiguration {
        var seen = Set<String>()
        let glossaryKeywords = context.isTerminologyGlossaryEnabled
            ? context.terminologyGlossary.filter(\.isEnabled).map(\.term)
            : []
        let recallKeywords = (recall?.vocabularyHints ?? []) + (recall?.correctionHints ?? [])
        let keywords = (glossaryKeywords + recallKeywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }

        return LiveTranscriptionConfiguration(
            endpoint: baseConfiguration.endpoint,
            model: baseConfiguration.model,
            language: baseConfiguration.language,
            encoding: baseConfiguration.encoding,
            sampleRate: baseConfiguration.sampleRate,
            channels: baseConfiguration.channels,
            interimResults: baseConfiguration.interimResults,
            punctuate: baseConfiguration.punctuate,
            smartFormat: baseConfiguration.smartFormat,
            vadEvents: baseConfiguration.vadEvents,
            endpointingMilliseconds: baseConfiguration.endpointingMilliseconds,
            utteranceEndMilliseconds: baseConfiguration.utteranceEndMilliseconds,
            keywords: Array(keywords.prefix(100))
        )
    }

    private func makePolishContext(
        base: UserProfileContext,
        recall: RecallBundle?
    ) -> UserProfileContext {
        guard let recall else {
            return base
        }

        let additions = (recall.styleHints + recall.sceneHints)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !additions.isEmpty else {
            return base
        }

        var updated = base
        let prefix = updated.memoryProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.memoryProfile = prefix.isEmpty ? additions : "\(prefix)\n\n\(additions)"
        return updated
    }

    private func makeActiveInputHints(
        context: UserProfileContext,
        recall: RecallBundle?
    ) -> [String] {
        var hints: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard seen.insert(trimmed.lowercased()).inserted else { return }
            hints.append(trimmed)
        }

        for hint in profileHints(from: context.memoryProfile).prefix(2) {
            append("风格·\(hint)")
        }

        if context.isTerminologyGlossaryEnabled {
            for term in context.terminologyGlossary where term.isEnabled {
                append("术语·\(term.term)")
                if hints.count >= 6 {
                    return Array(hints.prefix(6))
                }
            }
        }

        guard let recall else {
            return Array(hints.prefix(6))
        }

        for term in recall.vocabularyHints.prefix(2) {
            append("术语·\(term)")
        }

        for hint in recall.styleHints.prefix(2) {
            append(displayHint(forStyleHint: hint))
        }

        for hint in recall.sceneHints.prefix(1) {
            append("场景·\(hint)")
        }

        return Array(hints.prefix(6))
    }

    private func profileHints(from memoryProfile: String) -> [String] {
        memoryProfile
            .split(whereSeparator: \.isNewline)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-•"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .compactMap { line in
                let prefixes = ["偏好：", "偏好:", "风格：", "风格:"]
                for prefix in prefixes where line.hasPrefix(prefix) {
                    let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
                return nil
            }
    }

    private func displayHint(forStyleHint hint: String) -> String {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "brevity=short" {
            return "风格·简短"
        }
        if trimmed == "brevity=long" {
            return "风格·展开"
        }
        if trimmed == "tone=polite" {
            return "风格·礼貌"
        }
        if trimmed == "tone=casual" {
            return "风格·自然"
        }
        if trimmed.hasPrefix("tone=") {
            return "风格·" + trimmed.replacingOccurrences(of: "tone=", with: "")
        }
        if trimmed.hasPrefix("brevity=") {
            return "风格·" + trimmed.replacingOccurrences(of: "brevity=", with: "")
        }
        return "风格·\(trimmed)"
    }

    private func currentRecallBundle() async -> RecallBundle? {
        guard await memoryRecallEnabled() else {
            return nil
        }
        guard let memoryRetriever,
              let snapshot = await focusedSnapshotProvider?.currentFocusedInputSnapshot() else {
            return nil
        }

        let request = RecallRequest(
            timestamp: Date(),
            appIdentifier: snapshot.appIdentifier,
            windowTitle: snapshot.windowTitle,
            pageTitle: snapshot.pageTitle,
            fieldRole: snapshot.fieldRole,
            fieldLabel: snapshot.fieldLabel,
            requestedCapabilities: [.transcription, .polish]
        )

        do {
            let bundle = try await memoryRetriever.recall(for: request)
            diagnostics?.recordMemoryEvent(
                "Loaded recall bundle",
                metadata: ["summary": bundle.diagnosticSummary]
            )
            return bundle
        } catch {
            diagnostics?.recordMemoryEvent(
                "Recall lookup failed",
                severity: .warning,
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func polishTranscriptIfNeeded(
        _ transcript: String,
        context: UserProfileContext
    ) async -> String {
        guard context.polishMode != .off else { return transcript }
        guard let transcriptPostProcessor else { return transcript }

        do {
            let polishStartedAt = Date()
            let polished = try await transcriptPostProcessor.polish(
                transcript: transcript,
                context: context
            )
            performanceLog(
                "polish finished, mode=\(context.polishMode.rawValue), polishLatency=\(String(format: "%.3f", Date().timeIntervalSince(polishStartedAt)))s"
            )
            let validated = validatePolishedTranscript(
                polished,
                fallback: transcript,
                mode: context.polishMode
            )
            if validated != transcript {
                lastPolishFallbackReason = nil
            }
            return validated
        } catch {
            performanceLog(
                "polish failed, mode=\(context.polishMode.rawValue), error=\(error.localizedDescription)"
            )
            lastPolishFallbackReason = error.localizedDescription.isEmpty
                ? "Polish request failed."
                : error.localizedDescription
            return transcript
        }
    }

    private func shouldAttemptPolish(
        transcript: String,
        context: UserProfileContext
    ) -> Bool {
        guard context.polishMode != .off else { return false }
        guard transcriptPostProcessor != nil else { return false }

        if context.skipShortPolish {
            let contentCount = polishContentCharacterCount(in: transcript)
            if contentCount < max(1, context.shortPolishCharacterThreshold) {
                return false
            }
        }

        return true
    }

    private func validatePolishedTranscript(
        _ polished: String,
        fallback: String,
        mode: TranscriptPolishMode
    ) -> String {
        let candidate = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            lastPolishFallbackReason = "Polish output was empty."
            return fallback
        }

        let policy = validationPolicy(for: mode)
        let fallbackCount = max(fallback.count, 1)
        let minimumAllowed = Int(Double(fallbackCount) * policy.minimumLengthRatio)
        let maximumAllowed = Int(Double(fallbackCount) * policy.maximumLengthRatio)

        if candidate.count < minimumAllowed || candidate.count > maximumAllowed {
            lastPolishFallbackReason = "Polish output length was outside the safe range."
            return fallback
        }

        let similarity = similarityScore(candidate, fallback)
        if similarity < policy.minimumSimilarity {
            lastPolishFallbackReason = "Polish output changed the transcript too much."
            return fallback
        }

        return candidate
    }

    private func validationPolicy(for mode: TranscriptPolishMode) -> PolishValidationPolicy {
        switch mode {
        case .off:
            PolishValidationPolicy(
                minimumLengthRatio: 0.5,
                maximumLengthRatio: 1.8,
                minimumSimilarity: 0.55
            )
        case .light:
            PolishValidationPolicy(
                minimumLengthRatio: 0.55,
                maximumLengthRatio: 1.65,
                minimumSimilarity: 0.6
            )
        case .chat:
            PolishValidationPolicy(
                minimumLengthRatio: 0.45,
                maximumLengthRatio: 2.0,
                minimumSimilarity: 0.45
            )
        case .reply:
            PolishValidationPolicy(
                minimumLengthRatio: 0.4,
                maximumLengthRatio: 1.9,
                minimumSimilarity: 0.42
            )
        }
    }

    private func similarityScore(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedContent(lhs)
        let right = normalizedContent(rhs)

        guard !left.isEmpty, !right.isEmpty else { return 0 }

        var leftCounts: [Character: Int] = [:]
        for character in left {
            leftCounts[character, default: 0] += 1
        }

        var rightCounts: [Character: Int] = [:]
        for character in right {
            rightCounts[character, default: 0] += 1
        }

        let sharedCount = leftCounts.reduce(into: 0) { result, entry in
            result += min(entry.value, rightCounts[entry.key, default: 0])
        }

        return Double(sharedCount * 2) / Double(left.count + right.count)
    }

    private func normalizedContent(_ text: String) -> [Character] {
        Array(
            text
            .lowercased()
            .filter { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.alphanumerics.contains(scalar)
                }
            }
        )
    }

    private func polishContentCharacterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.unicodeScalars.contains(where: { scalar in
                CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
            }) {
                count += 1
            }
        }
    }

    private func recordMemoryEventIfNeeded(
        transcript: String,
        polishedTranscript: String,
        completedAt: Date,
        completedDuration: TimeInterval?,
        deliveryOutcome: TranscriptDeliveryOutcome
    ) async {
        guard await memoryCaptureEnabled() else {
            return
        }
        guard let memoryRecorder,
              let snapshot = await focusedSnapshotProvider?.currentFocusedInputSnapshot() else {
            return
        }

        let classifier = SensitiveFieldClassifier(
            optedOutApps: await memoryOptedOutApps(),
            optedOutFieldLabels: await memoryOptedOutFieldLabels()
        )
        let sensitivity = classifier.classify(snapshot)
        let observedText = sensitivity == .normal || sensitivity == .redacted
            ? await focusedSnapshotProvider?.observedTextAfterPublish()
            : nil
        let trimmedObservedText = observedText?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let trimmedInsertedText = polishedTranscript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let observationStatus: ObservationStatus
        if sensitivity == .secureExcluded || sensitivity == .optOut {
            observationStatus = .blockedSensitive
        } else if trimmedObservedText == nil {
            observationStatus = .unavailable
        } else if trimmedObservedText == trimmedInsertedText {
            observationStatus = .observedNoChange
        } else {
            observationStatus = .observedFinal
        }

        let event = InputEvent(
            id: UUID(),
            timestamp: completedAt,
            languageCode: primaryLanguageCode(from: baseConfiguration.language),
            localeIdentifier: Locale.current.identifier,
            appIdentifier: snapshot.appIdentifier,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle,
            pageTitle: snapshot.pageTitle,
            fieldRole: snapshot.fieldRole,
            fieldLabel: snapshot.fieldLabel,
            sensitivityClass: sensitivity,
            observationStatus: observationStatus,
            actionType: polishedTranscript == transcript ? .transcribe : .polish,
            rawTranscript: rawFinalTranscript,
            polishedText: polishedTranscript == transcript ? nil : polishedTranscript,
            insertedText: polishedTranscript,
            finalUserEditedText: observedText,
            outcome: inputOutcome(for: deliveryOutcome),
            durationMs: Int((completedDuration ?? 0) * 1000),
            source: .speech
        )

        do {
            try await memoryRecorder.record(event: event)
            diagnostics?.recordMemoryEvent(
                "Recorded memory event",
                metadata: [
                    "app": snapshot.appIdentifier,
                    "sensitivity": sensitivity.rawValue,
                    "observation": observationStatus.rawValue
                ]
            )
        } catch {
            diagnostics?.recordMemoryEvent(
                "Memory event recording failed",
                severity: .warning,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func primaryLanguageCode(from language: String) -> String {
        language.split(separator: "-").first.map(String.init) ?? language
    }

    private func inputOutcome(for deliveryOutcome: TranscriptDeliveryOutcome) -> InputEventOutcome {
        switch deliveryOutcome {
        case .insertedIntoFocusedApp, .typedIntoFocusedApp, .pasteShortcutSent, .copiedToClipboard, .publishedOnly:
            return .published
        }
    }
}

private struct PolishValidationPolicy {
    let minimumLengthRatio: Double
    let maximumLengthRatio: Double
    let minimumSimilarity: Double
}
