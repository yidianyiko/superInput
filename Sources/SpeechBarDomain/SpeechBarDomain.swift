import Foundation

public enum HardwareSourceKind: String, Sendable, Equatable {
    case onScreenButton
    case globalSpaceKey
    case globalShortcut
    case globalRightCommandKey
    case keyboardRotaryTest
    case usbRotaryKnob
    case usbHID
}

public enum HardwareEventKind: String, Sendable, Equatable {
    case pushToTalkPressed
    case pushToTalkReleased
    case rotaryClockwise
    case rotaryCounterClockwise
}

public struct HardwareEvent: Sendable, Equatable {
    public let source: HardwareSourceKind
    public let kind: HardwareEventKind
    public let occurredAt: Date

    public init(
        source: HardwareSourceKind,
        kind: HardwareEventKind,
        occurredAt: Date = Date()
    ) {
        self.source = source
        self.kind = kind
        self.occurredAt = occurredAt
    }
}

public enum AppIntent: Sendable, Equatable {
    case startVoiceCapture(source: HardwareSourceKind)
    case stopVoiceCapture(source: HardwareSourceKind)
    case switchWindow(direction: WindowSwitchDirection, source: HardwareSourceKind)
}

public enum WindowSwitchDirection: String, Sendable, Equatable {
    case previous
    case next
}

public enum WindowSwitchOutcome: Sendable, Equatable {
    case switchedWindow
    case switchedApplication
    case unavailable
    case permissionDenied
}

public struct WindowSwitchPreviewItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let appName: String
    public let title: String

    public init(
        id: String,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        appName: String,
        title: String
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
    }
}

public enum SpeechSessionState: Sendable, Equatable {
    case idle
    case requestingPermission
    case connecting
    case recording
    case finalizing
    case failed(String)
}

public enum AudioInputPermissionStatus: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

public struct AudioEncodingDescriptor: Sendable, Equatable {
    public let sampleRate: Int
    public let channelCount: Int
    public let encoding: String

    public init(sampleRate: Int, channelCount: Int, encoding: String) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.encoding = encoding
    }

    public static let deepgramLinear16 = AudioEncodingDescriptor(
        sampleRate: 16_000,
        channelCount: 1,
        encoding: "linear16"
    )
}

public struct AudioChunk: Sendable, Equatable {
    public let data: Data
    public let format: AudioEncodingDescriptor
    public let sequenceNumber: Int64

    public init(data: Data, format: AudioEncodingDescriptor, sequenceNumber: Int64) {
        self.data = data
        self.format = format
        self.sequenceNumber = sequenceNumber
    }
}

public enum TranscriptEvent: Sendable, Equatable {
    case opened
    case speechStarted
    case interim(String)
    case final(String)
    case utteranceEnded
    case metadata(requestID: String?)
    case error(String)
    case closed
}

public struct PublishedTranscript: Sendable, Equatable {
    public let text: String
    public let createdAt: Date

    public init(text: String, createdAt: Date = Date()) {
        self.text = text
        self.createdAt = createdAt
    }
}

public enum TranscriptDeliveryOutcome: Sendable, Equatable {
    case insertedIntoFocusedApp
    case typedIntoFocusedApp
    case pasteShortcutSent
    case copiedToClipboard
    case publishedOnly
}

public enum CredentialStatus: Sendable, Equatable {
    case missing
    case available
}

public struct TerminologyEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var term: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), term: String, isEnabled: Bool = true) {
        self.id = id
        self.term = term
        self.isEnabled = isEnabled
    }
}

public enum TranscriptPolishMode: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    case light
    case chat
}

public struct UserProfileContext: Sendable, Equatable, Codable {
    public var profession: String
    public var memoryProfile: String
    public var terminologyGlossary: [TerminologyEntry]
    public var isTerminologyGlossaryEnabled: Bool
    public var polishMode: TranscriptPolishMode
    public var skipShortPolish: Bool
    public var shortPolishCharacterThreshold: Int
    public var useClipboardContextForPolish: Bool
    public var useFrontmostAppContextForPolish: Bool
    public var polishTimeoutSeconds: Double

    public init(
        profession: String = "",
        memoryProfile: String = "",
        terminologyGlossary: [TerminologyEntry] = [],
        isTerminologyGlossaryEnabled: Bool = true,
        polishMode: TranscriptPolishMode = .light,
        skipShortPolish: Bool = true,
        shortPolishCharacterThreshold: Int = 8,
        useClipboardContextForPolish: Bool = false,
        useFrontmostAppContextForPolish: Bool = true,
        polishTimeoutSeconds: Double = 1.8
    ) {
        self.profession = profession
        self.memoryProfile = memoryProfile
        self.terminologyGlossary = terminologyGlossary
        self.isTerminologyGlossaryEnabled = isTerminologyGlossaryEnabled
        self.polishMode = polishMode
        self.skipShortPolish = skipShortPolish
        self.shortPolishCharacterThreshold = shortPolishCharacterThreshold
        self.useClipboardContextForPolish = useClipboardContextForPolish
        self.useFrontmostAppContextForPolish = useFrontmostAppContextForPolish
        self.polishTimeoutSeconds = polishTimeoutSeconds
    }
}

public struct AudioLevelSample: Sendable, Equatable {
    public let level: Double
    public let peak: Double
    public let capturedAt: Date

    public init(level: Double, peak: Double, capturedAt: Date = Date()) {
        self.level = level
        self.peak = peak
        self.capturedAt = capturedAt
    }
}

public enum RecordingOverlayPhase: Sendable, Equatable {
    case hidden
    case recording
    case finalizing
    case polishing
    case publishing
    case failed
}

public struct LiveTranscriptionConfiguration: Sendable, Equatable {
    public let endpoint: URL
    public let model: String
    public let language: String
    public let encoding: String
    public let sampleRate: Int
    public let channels: Int
    public let interimResults: Bool
    public let punctuate: Bool
    public let smartFormat: Bool
    public let vadEvents: Bool
    public let endpointingMilliseconds: Int
    public let utteranceEndMilliseconds: Int
    public let keywords: [String]

    public init(
        endpoint: URL = URL(string: "wss://api.deepgram.com/v1/listen")!,
        model: String = "nova-2",
        language: String = "zh-CN",
        encoding: String = "linear16",
        sampleRate: Int = 16_000,
        channels: Int = 1,
        interimResults: Bool = true,
        punctuate: Bool = true,
        smartFormat: Bool = true,
        vadEvents: Bool = true,
        endpointingMilliseconds: Int = 300,
        utteranceEndMilliseconds: Int = 1_000,
        keywords: [String] = []
    ) {
        self.endpoint = endpoint
        self.model = model
        self.language = language
        self.encoding = encoding
        self.sampleRate = sampleRate
        self.channels = channels
        self.interimResults = interimResults
        self.punctuate = punctuate
        self.smartFormat = smartFormat
        self.vadEvents = vadEvents
        self.endpointingMilliseconds = endpointingMilliseconds
        self.utteranceEndMilliseconds = utteranceEndMilliseconds
        self.keywords = keywords
    }

    public var websocketURL: URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "encoding", value: encoding),
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "channels", value: String(channels)),
            URLQueryItem(name: "interim_results", value: interimResults.description),
            URLQueryItem(name: "punctuate", value: punctuate.description),
            URLQueryItem(name: "smart_format", value: smartFormat.description),
            URLQueryItem(name: "vad_events", value: vadEvents.description),
            URLQueryItem(name: "endpointing", value: String(endpointingMilliseconds)),
            URLQueryItem(name: "utterance_end_ms", value: String(utteranceEndMilliseconds))
        ]
        return components.url!
    }

    public var prerecordedURL: URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        // The base endpoint uses wss:// for live streaming, but the prerecorded
        // API requires https://.
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        var queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "punctuate", value: punctuate.description),
            URLQueryItem(name: "smart_format", value: smartFormat.description)
        ]
        queryItems.append(
            contentsOf: keywords.map { keyword in
                URLQueryItem(name: "keywords", value: "\(keyword):2")
            }
        )
        components.queryItems = queryItems
        return components.url!
    }
}

public protocol HardwareEventSource: Sendable {
    var events: AsyncStream<HardwareEvent> { get }
}

public protocol AudioInputSource: Sendable {
    var audioLevels: AsyncStream<AudioLevelSample> { get }
    func requestRecordPermission() async -> AudioInputPermissionStatus
    func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error>
    func stopCapture() async
}

public protocol TranscriptionClient: Sendable {
    var events: AsyncStream<TranscriptEvent> { get }
    func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws
    func send(audioChunk: AudioChunk) async throws
    func finalize() async throws
    func close() async
}

public protocol CredentialProvider: Sendable {
    func credentialStatus() -> CredentialStatus
    func loadAPIKey() throws -> String
    func save(apiKey: String) throws
    func deleteAPIKey() throws
}

public protocol TranscriptPublisher: Sendable {
    func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome
}

public protocol WindowSwitching: Sendable {
    func switchWindow(direction: WindowSwitchDirection) async -> WindowSwitchOutcome
}

public protocol WindowSwitchPreviewPublishing: Sendable {
    func showWindowSwitchPreview(items: [WindowSwitchPreviewItem], selectedIndex: Int) async
    func hideWindowSwitchPreview() async
}

public protocol TranscriptTargetCapturing: Sendable {
    func captureCurrentTarget() async
    func clearCapturedTarget() async
}

public protocol SleepClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public protocol UserProfileContextProviding: Sendable {
    func currentContext() async -> UserProfileContext
}

public protocol TerminologyResearchClient: Sendable {
    func generateTerminology(
        profession: String,
        memoryProfile: String
    ) async throws -> [TerminologyEntry]
}

public protocol TranscriptPostProcessor: Sendable {
    func polish(
        transcript: String,
        context: UserProfileContext
    ) async throws -> String
}

public struct ContinuousSleepClock: SleepClock {
    private let clock = ContinuousClock()

    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}
