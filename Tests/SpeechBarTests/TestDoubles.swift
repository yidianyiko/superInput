import CoreGraphics
import Foundation
import MemoryDomain
@testable import SpeechBarApp
@testable import SpeechBarInfrastructure
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

final class MockRecordingHotkeyRuntimeSource: RecordingHotkeyRuntimeSource, @unchecked Sendable {
    let events: AsyncStream<HardwareEvent>
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>
    let requiresAccessibility: Bool

    private let eventsContinuation: AsyncStream<HardwareEvent>.Continuation
    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation

    private(set) var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot
    private(set) var shutdownCallCount = 0
    private var isShutdown = false

    init(
        diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot,
        requiresAccessibility: Bool? = nil
    ) {
        var capturedEventsContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedEventsContinuation = continuation
        }
        self.eventsContinuation = capturedEventsContinuation!

        var capturedDiagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation?
        self.diagnosticsUpdates = AsyncStream { continuation in
            capturedDiagnosticsContinuation = continuation
        }
        self.diagnosticsContinuation = capturedDiagnosticsContinuation!
        self.diagnosticsSnapshot = diagnosticsSnapshot
        self.requiresAccessibility = requiresAccessibility ?? diagnosticsSnapshot.requiresAccessibility
        self.diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    func send(_ event: HardwareEvent) {
        guard !isShutdown else { return }
        eventsContinuation.yield(event)
    }

    func updateDiagnostics(_ diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot) {
        guard !isShutdown else { return }
        self.diagnosticsSnapshot = diagnosticsSnapshot
        diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    func shutdown() {
        shutdownCallCount += 1
        guard !isShutdown else { return }
        isShutdown = true
        eventsContinuation.finish()
        diagnosticsContinuation.finish()
    }
}

final class MockRecordingHotkeySettingsController: RecordingHotkeySettingsControlling, @unchecked Sendable {
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>

    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation

    private(set) var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot
    private(set) var appliedConfigurations: [RecordingHotkeyConfiguration] = []

    init(diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot) {
        var capturedDiagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation?
        self.diagnosticsUpdates = AsyncStream { continuation in
            capturedDiagnosticsContinuation = continuation
        }
        self.diagnosticsContinuation = capturedDiagnosticsContinuation!
        self.diagnosticsSnapshot = diagnosticsSnapshot
    }

    func apply(_ configuration: RecordingHotkeyConfiguration) {
        appliedConfigurations.append(configuration)
        diagnosticsSnapshot = Self.recomputedDiagnostics(
            previous: diagnosticsSnapshot,
            configuration: configuration
        )
        diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    func emitDiagnostics(_ diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot) {
        self.diagnosticsSnapshot = diagnosticsSnapshot
        diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    private static func recomputedDiagnostics(
        previous: RecordingHotkeyDiagnosticsSnapshot,
        configuration: RecordingHotkeyConfiguration
    ) -> RecordingHotkeyDiagnosticsSnapshot {
        let requiresAccessibility = configuration.mode == .rightCommand
        let accessibilityTrusted = requiresAccessibility ? previous.accessibilityTrusted : true

        let registrationStatus: RecordingHotkeyRegistrationStatus
        let guidanceText: String?

        switch configuration.mode {
        case .rightCommand:
            if accessibilityTrusted {
                registrationStatus = .registered
                guidanceText = nil
            } else {
                registrationStatus = .permissionRequired
                guidanceText = "Grant Accessibility access to use the right Command hotkey."
            }
        case .customCombo:
            if configuration.customCombination.validationResult == .valid {
                registrationStatus = .registered
                guidanceText = nil
            } else {
                registrationStatus = .invalidConfiguration
                guidanceText = "Choose a valid custom hotkey combination."
            }
        }

        return RecordingHotkeyDiagnosticsSnapshot(
            configuration: configuration,
            registrationStatus: registrationStatus,
            requiresAccessibility: requiresAccessibility,
            accessibilityTrusted: accessibilityTrusted,
            lastTrigger: previous.lastTrigger,
            guidanceText: guidanceText
        )
    }
}

final class MockAudioInputSource: AudioInputSource, @unchecked Sendable {
    let audioLevels: AsyncStream<AudioLevelSample>
    private let levelsContinuation: AsyncStream<AudioLevelSample>.Continuation
    var permissionStatus: AudioInputPermissionStatus = .granted
    var startError: Error?
    private(set) var startCallCount = 0
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
        startCallCount += 1

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
    var error: Error?

    func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome {
        if let error {
            throw error
        }
        published.append(transcript)
        return outcome
    }

    func setOutcome(_ outcome: TranscriptDeliveryOutcome) {
        self.outcome = outcome
    }

    func setError(_ error: Error?) {
        self.error = error
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

struct MockTranscriptInjectionTargetSnapshotProvider: TranscriptInjectionTargetSnapshotProviding {
    var snapshot: TranscriptInjectionTargetSnapshot?

    init(
        snapshot: TranscriptInjectionTargetSnapshot? = TranscriptInjectionTargetSnapshot(
            processIdentifier: 4242,
            appIdentifier: "com.apple.TextEdit",
            appName: "TextEdit",
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            windowFrame: CGRect(x: 180, y: 160, width: 820, height: 520),
            elementFrame: CGRect(x: 260, y: 260, width: 360, height: 44),
            destinationPoint: CGPoint(x: 440, y: 282)
        )
    ) {
        self.snapshot = snapshot
    }

    func currentTranscriptInjectionTargetSnapshot() async -> TranscriptInjectionTargetSnapshot? {
        snapshot
    }
}

struct ImmediateSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {}
}

struct ThrowingSleepClock: SleepClock {
    let error: any Error

    func sleep(for duration: Duration) async throws {
        throw error
    }
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
