import Foundation
import MemoryDomain
import SpeechBarDomain

final class MockHardwareEventSource: HardwareEventSource, @unchecked Sendable {
    let events: AsyncStream<HardwareEvent>
    private let continuation: AsyncStream<HardwareEvent>.Continuation

    init() {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    func send(_ event: HardwareEvent) {
        continuation.yield(event)
    }
}

final class MockAudioInputSource: AudioInputSource, @unchecked Sendable {
    let audioLevels: AsyncStream<AudioLevelSample>
    private let levelsContinuation: AsyncStream<AudioLevelSample>.Continuation
    var permissionStatus: AudioInputPermissionStatus = .granted
    var startError: Error?
    private(set) var stopCallCount = 0
    private var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?

    init() {
        var capturedLevelsContinuation: AsyncStream<AudioLevelSample>.Continuation?
        self.audioLevels = AsyncStream { continuation in
            capturedLevelsContinuation = continuation
        }
        self.levelsContinuation = capturedLevelsContinuation!
    }

    func requestRecordPermission() async -> AudioInputPermissionStatus {
        permissionStatus
    }

    func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        if let startError {
            throw startError
        }

        return AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func emit(_ chunk: AudioChunk) {
        continuation?.yield(chunk)
    }

    func emit(level: AudioLevelSample) {
        levelsContinuation.yield(level)
    }

    func finish() {
        continuation?.finish()
    }

    func stopCapture() async {
        stopCallCount += 1
        continuation?.finish()
        continuation = nil
    }
}

final class MockTranscriptionClient: TranscriptionClient, @unchecked Sendable {
    let events: AsyncStream<TranscriptEvent>
    private let continuation: AsyncStream<TranscriptEvent>.Continuation

    private(set) var connectCallCount = 0
    private(set) var finalizeCallCount = 0
    private(set) var closeCallCount = 0
    private(set) var sentChunks: [AudioChunk] = []
    private(set) var lastConfiguration: LiveTranscriptionConfiguration?

    var connectError: Error?
    var finalizeError: Error?
    var finalizeDelay: Duration?

    init() {
        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        connectCallCount += 1
        lastConfiguration = configuration
        if let connectError {
            throw connectError
        }
        continuation.yield(.opened)
    }

    func send(audioChunk: AudioChunk) async throws {
        sentChunks.append(audioChunk)
    }

    func finalize() async throws {
        finalizeCallCount += 1
        if let finalizeDelay {
            try await Task.sleep(for: finalizeDelay)
        }
        if let finalizeError {
            throw finalizeError
        }
    }

    func close() async {
        closeCallCount += 1
        continuation.yield(.closed)
    }

    func emit(_ event: TranscriptEvent) {
        continuation.yield(event)
    }
}

struct MockCredentialProvider: CredentialProvider {
    var storedAPIKey: String?

    func credentialStatus() -> CredentialStatus {
        storedAPIKey == nil ? .missing : .available
    }

    func loadAPIKey() throws -> String {
        guard let storedAPIKey else {
            throw NSError(domain: "MockCredentialProvider", code: 404)
        }
        return storedAPIKey
    }

    func save(apiKey: String) throws {}

    func deleteAPIKey() throws {}
}

actor MockTranscriptPublisher: TranscriptPublisher {
    private(set) var published: [PublishedTranscript] = []
    var outcome: TranscriptDeliveryOutcome = .publishedOnly

    func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome {
        published.append(transcript)
        return outcome
    }

    func setOutcome(_ outcome: TranscriptDeliveryOutcome) {
        self.outcome = outcome
    }

    func snapshot() -> [PublishedTranscript] {
        published
    }
}

actor MockWindowSwitcher: WindowSwitching {
    private var directions: [WindowSwitchDirection] = []
    var outcome: WindowSwitchOutcome = .switchedWindow

    func switchWindow(direction: WindowSwitchDirection) async -> WindowSwitchOutcome {
        directions.append(direction)
        return outcome
    }

    func snapshot() -> [WindowSwitchDirection] {
        return directions
    }
}

final class MockReturnKeyPressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func press() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

actor MockMemoryRecorder: MemoryEventRecording {
    private(set) var recordedEvents: [InputEvent] = []

    func record(event: InputEvent) async throws {
        recordedEvents.append(event)
    }

    var recordedEventCount: Int {
        get async { recordedEvents.count }
    }

    func snapshot() -> [InputEvent] {
        recordedEvents
    }
}

struct MockMemoryRetriever: MemoryRetriever {
    var bundle: RecallBundle

    func recall(for request: RecallRequest) async throws -> RecallBundle {
        bundle
    }
}

struct MockFocusedInputSnapshotProvider: FocusedInputSnapshotProviding {
    var snapshot: FocusedInputSnapshot? = FocusedInputSnapshot(
        appIdentifier: "com.apple.TextEdit",
        appName: "TextEdit",
        windowTitle: "Untitled",
        pageTitle: nil,
        fieldRole: "AXTextArea",
        fieldLabel: "Body",
        isEditable: true,
        isSecure: false
    )
    var observedText: String? = "ni hao"

    func currentFocusedInputSnapshot() async -> FocusedInputSnapshot? {
        snapshot
    }

    func observedTextAfterPublish() async -> String? {
        observedText
    }
}

struct ImmediateSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {}
}

struct MockUserProfileContextProvider: UserProfileContextProviding {
    var context = UserProfileContext()

    func currentContext() async -> UserProfileContext {
        context
    }
}

final class MockTranscriptPostProcessor: TranscriptPostProcessor, @unchecked Sendable {
    var polishedText: String?
    var error: Error?
    private(set) var receivedTranscripts: [String] = []
    private(set) var receivedContexts: [UserProfileContext] = []

    func polish(
        transcript: String,
        context: UserProfileContext
    ) async throws -> String {
        receivedTranscripts.append(transcript)
        receivedContexts.append(context)
        if let error {
            throw error
        }
        return polishedText ?? transcript
    }
}
