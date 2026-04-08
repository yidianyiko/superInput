import Combine
import Foundation
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
    @Published public private(set) var sessionState: SpeechSessionState = .idle
    @Published public private(set) var rawFinalTranscript = ""
    @Published public private(set) var interimTranscript = ""
    @Published public private(set) var finalTranscript = ""
    @Published public private(set) var statusMessage = "已就绪"
    @Published public private(set) var credentialStatus: CredentialStatus = .missing
    @Published public private(set) var isPushToTalkActive = false
    @Published public private(set) var lastCompletedTranscript: PublishedTranscript?
    @Published public private(set) var lastDeliveryOutcome: TranscriptDeliveryOutcome?
    @Published public private(set) var lastCompletedSessionDuration: TimeInterval?
    @Published public private(set) var lastPolishFallbackReason: String?
    @Published public private(set) var overlayPhase: RecordingOverlayPhase = .hidden
    @Published public private(set) var overlaySubtitle = ""
    @Published public private(set) var audioLevelWindow: [AudioLevelSample] = []

    private let hardwareSource: any HardwareEventSource
    private let audioInputSource: any AudioInputSource
    private let transcriptionClient: any TranscriptionClient
    private let credentialProvider: any CredentialProvider
    private let transcriptPublisher: any TranscriptPublisher
    private let streamingTranscriptPublisher: (any StreamingTranscriptPublisher)?
    private let windowSwitcher: (any WindowSwitching)?
    private let transcriptTargetCapturer: (any TranscriptTargetCapturing)?
    private let userProfileProvider: (any UserProfileContextProviding)?
    private let transcriptPostProcessor: (any TranscriptPostProcessor)?
    private let baseConfiguration: LiveTranscriptionConfiguration
    private let sleepClock: any SleepClock
    private let shouldUseIncrementalInterimPublishing: @Sendable () -> Bool

    private var hardwareTask: Task<Void, Never>?
    private var transcriptionEventTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?
    private var finalizeTimeoutTask: Task<Void, Never>?

    private var hasStarted = false
    private var activeSessionID: UUID?
    private var activeSessionStartedAt: Date?
    private var activeFinalizeStartedAt: Date?
    private var shouldFinalizeWhenReady = false
    private var isCompletingActiveSession = false
    private var finalSegments: [String] = []
    private var isTranscriptionConnectionReady = false
    private var pendingConnectionAudioChunks: [AudioChunk] = []
    private var pendingConnectionAudioBytes = 0
    private let maxPendingConnectionAudioBytes = 160_000
    private let finalizeRequestTimeout: Duration = .seconds(10)
    private var isStreamingInterimPublishingActive = false

    public init(
        hardwareSource: any HardwareEventSource,
        audioInputSource: any AudioInputSource,
        transcriptionClient: any TranscriptionClient,
        credentialProvider: any CredentialProvider,
        transcriptPublisher: any TranscriptPublisher,
        streamingTranscriptPublisher: (any StreamingTranscriptPublisher)? = nil,
        windowSwitcher: (any WindowSwitching)? = nil,
        transcriptTargetCapturer: (any TranscriptTargetCapturing)? = nil,
        userProfileProvider: (any UserProfileContextProviding)? = nil,
        transcriptPostProcessor: (any TranscriptPostProcessor)? = nil,
        configuration: LiveTranscriptionConfiguration = LiveTranscriptionConfiguration(),
        sleepClock: any SleepClock = ContinuousSleepClock(),
        shouldUseIncrementalInterimPublishing: @escaping @Sendable () -> Bool = { false }
    ) {
        self.hardwareSource = hardwareSource
        self.audioInputSource = audioInputSource
        self.transcriptionClient = transcriptionClient
        self.credentialProvider = credentialProvider
        self.transcriptPublisher = transcriptPublisher
        self.streamingTranscriptPublisher = streamingTranscriptPublisher
        self.windowSwitcher = windowSwitcher
        self.transcriptTargetCapturer = transcriptTargetCapturer
        self.userProfileProvider = userProfileProvider
        self.transcriptPostProcessor = transcriptPostProcessor
        self.baseConfiguration = configuration
        self.sleepClock = sleepClock
        self.shouldUseIncrementalInterimPublishing = shouldUseIncrementalInterimPublishing
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
        }
    }

    private func mapAppIntent(from event: HardwareEvent) -> AppIntent {
        switch event.kind {
        case .pushToTalkPressed:
            return .startVoiceCapture(source: event.source)
        case .pushToTalkReleased:
            return .stopVoiceCapture(source: event.source)
        case .rotaryClockwise:
            return .switchWindow(direction: .next, source: event.source)
        case .rotaryCounterClockwise:
            return .switchWindow(direction: .previous, source: event.source)
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
        isStreamingInterimPublishingActive = shouldUseIncrementalInterimPublishing()
        finalSegments = []
        isTranscriptionConnectionReady = false
        pendingConnectionAudioChunks = []
        pendingConnectionAudioBytes = 0
        rawFinalTranscript = ""
        interimTranscript = ""
        finalTranscript = ""
        lastPolishFallbackReason = nil
        statusMessage = "正在准备麦克风..."
        isPushToTalkActive = true
        sessionState = .requestingPermission
        activeSessionStartedAt = Date()
        overlayPhase = .recording
        overlaySubtitle = "监听中"
        audioLevelWindow = []
        if isStreamingInterimPublishingActive {
            await streamingTranscriptPublisher?.beginStreamingSession()
        }

        let permission = await audioInputSource.requestRecordPermission()
        guard isCurrentSession(sessionID) else { return }

        guard permission == .granted else {
            await failActiveSession(message: "需要授予麦克风权限。")
            return
        }

        let audioStream: AsyncThrowingStream<AudioChunk, Error>
        do {
            audioStream = try await audioInputSource.startCapture()
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            await failActiveSession(
                message: message.isEmpty ? "无法启动录音。" : message
            )
            return
        }

        guard isCurrentSession(sessionID) else {
            await audioInputSource.stopCapture()
            await transcriptionClient.close()
            return
        }

        let apiKey: String
        do {
            apiKey = try credentialProvider.loadAPIKey()
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            await failActiveSession(
                message: message.isEmpty ? "转写服务尚未准备好。" : message
            )
            return
        }

        audioTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in audioStream {
                    try await self.handleCapturedAudioChunk(chunk)
                }
            } catch is CancellationError {
                return
            } catch {
                await self.failActiveSession(message: "上传音频到转写服务失败。")
            }
        }

        sessionState = .connecting
        statusMessage = "正在连接转写服务..."

        let context = await currentUserProfileContext()
        let sessionConfiguration = makeSessionConfiguration(context: context)

        do {
            try await transcriptionClient.connect(apiKey: apiKey, configuration: sessionConfiguration)
        } catch {
            await failActiveSession(message: "无法连接转写服务。")
            return
        }

        guard isCurrentSession(sessionID) else {
            await transcriptionClient.close()
            return
        }

        isTranscriptionConnectionReady = true
        do {
            try await flushPendingConnectionAudioChunks()
        } catch {
            await failActiveSession(message: "上传音频到转写服务失败。")
            return
        }

        sessionState = .recording
        statusMessage = "正在监听..."
        overlayPhase = .recording
        overlaySubtitle = "监听中"

        if shouldFinalizeWhenReady {
            await finalizeActiveSession()
        }
    }

    private func endVoiceCapture() async {
        isPushToTalkActive = false

        switch sessionState {
        case .requestingPermission, .connecting:
            shouldFinalizeWhenReady = true
            statusMessage = "正在停止..."
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
        statusMessage = "正在完成转写..."
        shouldFinalizeWhenReady = false
        activeFinalizeStartedAt = Date()
        overlayPhase = .finalizing
        overlaySubtitle = "转写中"
        if let activeSessionStartedAt {
            performanceLog(
                "finalize started, captureDuration=\(String(format: "%.3f", Date().timeIntervalSince(activeSessionStartedAt)))s"
            )
        } else {
            performanceLog("finalize started")
        }

        await audioInputSource.stopCapture()

        do {
            try await finalizeTranscriptionRequest()
        } catch {
            await failActiveSession(message: "无法完成本次转写。")
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
                statusMessage = "转写连接已建立。"
            }

        case .speechStarted:
            if sessionState == .recording || sessionState == .finalizing {
                statusMessage = "已检测到语音。"
            }

        case .interim(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            interimTranscript = text
            if isStreamingInterimPublishingActive {
                do {
                    _ = try await streamingTranscriptPublisher?.updateStreamingTranscript(text)
                } catch {
                    performanceLog("streaming interim publish failed: \(error.localizedDescription)")
                }
            }
            if sessionState == .recording {
                statusMessage = "正在实时转写..."
            }

        case .final(let text):
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            finalSegments.append(cleaned)
            rawFinalTranscript = finalSegments.joined(separator: " ")
            finalTranscript = rawFinalTranscript
            interimTranscript = ""
            if isStreamingInterimPublishingActive {
                do {
                    _ = try await streamingTranscriptPublisher?.updateStreamingTranscript(rawFinalTranscript)
                } catch {
                    performanceLog("streaming final publish failed: \(error.localizedDescription)")
                }
            }
            statusMessage = "转写结果已更新。"

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

        var transcript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty, isStreamingInterimPublishingActive {
            transcript = interimTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if transcript.isEmpty {
            await failActiveSession(message: "没有检测到语音，请重试。")
            return
        }

        let context = await currentUserProfileContext()
        let polishedTranscript: String
        if shouldAttemptPolish(transcript: transcript, context: context) {
            overlayPhase = .polishing
            overlaySubtitle = "润色中"
            if let activeFinalizeStartedAt {
                performanceLog(
                    "transcription finished, rawChars=\(transcript.count), transcriptionLatency=\(String(format: "%.3f", Date().timeIntervalSince(activeFinalizeStartedAt)))s"
                )
            }
            polishedTranscript = await polishTranscriptIfNeeded(transcript, context: context)
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
        let completedDuration = activeSessionStartedAt.map {
            max(0, completedAt.timeIntervalSince($0))
        }
        let deliveryOutcome: TranscriptDeliveryOutcome
        do {
            overlayPhase = .publishing
            overlaySubtitle = isStreamingInterimPublishingActive ? "更新中" : "粘贴中"
            let publishStartedAt = Date()
            if isStreamingInterimPublishingActive, let streamingTranscriptPublisher {
                deliveryOutcome = try await streamingTranscriptPublisher.finishStreamingSession(
                    finalText: polishedTranscript
                )
            } else {
                deliveryOutcome = try await transcriptPublisher.publish(publishedTranscript)
            }
            performanceLog(
                "publish finished, publishLatency=\(String(format: "%.3f", Date().timeIntervalSince(publishStartedAt)))s"
            )
        } catch {
            await teardownActiveSession()
            sessionState = .idle
            overlayPhase = .hidden
            overlaySubtitle = ""
            statusMessage = error.localizedDescription.isEmpty
                ? "转写已完成，但无法插入到当前应用。"
                : error.localizedDescription
            return
        }

        lastCompletedTranscript = publishedTranscript
        lastDeliveryOutcome = deliveryOutcome
        lastCompletedSessionDuration = completedDuration
        if let activeFinalizeStartedAt {
            performanceLog(
                "session finished, endToEndFinalizeLatency=\(String(format: "%.3f", Date().timeIntervalSince(activeFinalizeStartedAt)))s"
            )
        }
        await teardownActiveSession()
        sessionState = .idle
        overlayPhase = .hidden
        overlaySubtitle = ""
        switch deliveryOutcome {
        case .insertedIntoFocusedApp:
            statusMessage = "转写内容已插入到当前应用。"
        case .typedIntoFocusedApp:
            statusMessage = "转写内容已实时输入到当前应用。"
        case .pasteShortcutSent:
            statusMessage = "转写完成，已发送粘贴，同时文本也已写入剪贴板。如未出现，请手动按 Command+V。"
        case .copiedToClipboard:
            statusMessage = "转写完成，文本已复制到剪贴板。请点击输入框后按 Command+V。"
        case .publishedOnly:
            statusMessage = "转写完成。"
        }
    }

    private func failActiveSession(message: String) async {
        await teardownActiveSession()
        sessionState = .failed(message)
        statusMessage = message
        overlayPhase = .failed
        overlaySubtitle = message
        audioLevelWindow = []
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
        audioLevelWindow = []
        isTranscriptionConnectionReady = false
        pendingConnectionAudioChunks = []
        pendingConnectionAudioBytes = 0
        isStreamingInterimPublishingActive = false

        await audioInputSource.stopCapture()
        await transcriptionClient.close()
        await streamingTranscriptPublisher?.cancelStreamingSession()
        await transcriptTargetCapturer?.clearCapturedTarget()
    }

    private func cancelActiveSession() async {
        guard activeSessionID != nil else { return }
        await teardownActiveSession()
        finalSegments = []
        isTranscriptionConnectionReady = false
        pendingConnectionAudioChunks = []
        pendingConnectionAudioBytes = 0
        isStreamingInterimPublishingActive = false
        rawFinalTranscript = ""
        interimTranscript = ""
        finalTranscript = ""
        lastPolishFallbackReason = nil
        sessionState = .idle
        overlayPhase = .hidden
        overlaySubtitle = ""
        statusMessage = "已取消录音。"
    }

    private func handleCapturedAudioChunk(_ chunk: AudioChunk) async throws {
        guard activeSessionID != nil else { return }

        if isTranscriptionConnectionReady {
            try await transcriptionClient.send(audioChunk: chunk)
            return
        }

        pendingConnectionAudioChunks.append(chunk)
        pendingConnectionAudioBytes += chunk.data.count

        while pendingConnectionAudioBytes > maxPendingConnectionAudioBytes,
              let first = pendingConnectionAudioChunks.first {
            pendingConnectionAudioChunks.removeFirst()
            pendingConnectionAudioBytes -= first.data.count
        }
    }

    private func flushPendingConnectionAudioChunks() async throws {
        guard !pendingConnectionAudioChunks.isEmpty else { return }
        let chunks = pendingConnectionAudioChunks
        pendingConnectionAudioChunks = []
        pendingConnectionAudioBytes = 0

        for chunk in chunks {
            try await transcriptionClient.send(audioChunk: chunk)
        }
    }

    private func finalizeTranscriptionRequest() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.transcriptionClient.finalize()
            }
            group.addTask {
                try await self.sleepClock.sleep(for: self.finalizeRequestTimeout)
                throw NSError(
                    domain: "VoiceSessionCoordinator",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Finalize timed out."]
                )
            }

            let result = try await group.next()
            group.cancelAll()
            _ = result
        }
    }

    private func isCurrentSession(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    private func handleAudioLevel(_ sample: AudioLevelSample) {
        guard activeSessionID != nil else { return }
        guard overlayPhase == .recording else { return }

        audioLevelWindow.append(sample)
        if audioLevelWindow.count > 24 {
            audioLevelWindow.removeFirst(audioLevelWindow.count - 24)
        }
    }

    private func currentUserProfileContext() async -> UserProfileContext {
        await userProfileProvider?.currentContext() ?? UserProfileContext()
    }

    private func makeSessionConfiguration(context: UserProfileContext) -> LiveTranscriptionConfiguration {
        guard context.isTerminologyGlossaryEnabled else {
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
                keywords: []
            )
        }

        var seen = Set<String>()
        let keywords = context.terminologyGlossary
            .filter(\.isEnabled)
            .map(\.term)
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
}

private struct PolishValidationPolicy {
    let minimumLengthRatio: Double
    let maximumLengthRatio: Double
    let minimumSimilarity: Double
}
