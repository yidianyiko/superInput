import Foundation
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

    func snapshot() -> [PublishedTranscript] {
        published
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

    func polish(
        transcript: String,
        context: UserProfileContext
    ) async throws -> String {
        receivedTranscripts.append(transcript)
        if let error {
            throw error
        }
        return polishedText ?? transcript
    }
}
