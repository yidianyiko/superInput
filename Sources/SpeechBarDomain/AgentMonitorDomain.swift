import Foundation

public enum AgentProvider: String, Sendable, Equatable, CaseIterable, Codable, Identifiable {
    case claudeCode
    case codexCLI
    case geminiCLI
    case cursorAgent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codexCLI:
            return "Codex CLI"
        case .geminiCLI:
            return "Gemini CLI"
        case .cursorAgent:
            return "Cursor Agent"
        }
    }

    public var shortLabel: String {
        switch self {
        case .claudeCode:
            return "Claude"
        case .codexCLI:
            return "Codex"
        case .geminiCLI:
            return "Gemini"
        case .cursorAgent:
            return "Cursor"
        }
    }

    public var symbolName: String {
        switch self {
        case .claudeCode:
            return "sparkles.rectangle.stack"
        case .codexCLI:
            return "terminal"
        case .geminiCLI:
            return "diamond"
        case .cursorAgent:
            return "cursorarrow.motionlines"
        }
    }
}

public enum AgentObservationKind: String, Sendable, Equatable, CaseIterable, Codable {
    case sessionStarted
    case taskStarted
    case toolStarted
    case toolFinished
    case agentOutput
    case waitingInput
    case waitingApproval
    case taskFinished
    case taskFailed
    case quotaUpdated
    case heartbeat
    case collectorError
}

public enum AgentRawPhase: String, Sendable, Equatable, Codable {
    case booting
    case running
    case waitingInput
    case waitingApproval
    case checking
    case finished
    case failed
    case stale
}

public enum BoardState: String, Sendable, Equatable, CaseIterable, Codable {
    case run = "RUN"
    case check = "CHECK"
    case input = "INPUT"
    case approve = "APPROVE"
    case error = "ERROR"

    public var priority: Int {
        switch self {
        case .error:
            return 5
        case .input:
            return 4
        case .approve:
            return 3
        case .check:
            return 2
        case .run:
            return 1
        }
    }
}

public enum TaskBoardLayoutMode: String, Sendable, Equatable, Codable {
    case stretched
    case fixed
}

public enum EmbeddedDisplayMode: String, Sendable, Equatable, Codable {
    case multiTaskBoard
    case audioWaveform
    case blank
    case booting
    case error
}

public enum DiagnosticSeverity: Int, Sendable, Equatable, Comparable, Codable, CaseIterable {
    case info = 0
    case warning = 1
    case error = 2
    case critical = 3

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum QuotaAvailability: String, Sendable, Equatable, Codable {
    case available
    case unknown
    case error
}

public enum EmbeddedTransportKind: String, Sendable, Equatable, Codable {
    case loopback
    case fileDump
    case hid
    case cdc
    case unknown
}

public enum EmbeddedBoardConnectionPhase: String, Sendable, Equatable, Codable {
    case disconnected
    case discovering
    case connecting
    case ready
    case degraded
    case failed
}

public enum EmbeddedBoardInputEventKind: String, Sendable, Equatable, Codable {
    case rotateNext
    case rotatePrevious
    case pressPrimary
    case pressSecondary
    case dismissSelected
}

public enum EmbeddedBoardPacketKind: String, Sendable, Equatable, Codable {
    case hello
    case displaySnapshotFrame
    case ping
    case requestDeviceStatus
    case setDisplayBrightness
    case goodbye
}

public struct AgentQuotaStatus: Sendable, Equatable, Codable {
    public var availability: QuotaAvailability
    public var remainingValue: Double?
    public var unit: String?
    public var sourceLabel: String?
    public var updatedAt: Date?

    public init(
        availability: QuotaAvailability = .unknown,
        remainingValue: Double? = nil,
        unit: String? = nil,
        sourceLabel: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.availability = availability
        self.remainingValue = remainingValue
        self.unit = unit
        self.sourceLabel = sourceLabel
        self.updatedAt = updatedAt
    }

    public static let unknown = AgentQuotaStatus()
}

public struct AgentObservationEvent: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let provider: AgentProvider
    public let sessionID: String
    public let timestamp: Date
    public let kind: AgentObservationKind
    public let title: String?
    public let message: String?
    public let workspacePath: String?
    public let rawSource: String?
    public let severity: DiagnosticSeverity
    public let traceID: String
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        provider: AgentProvider,
        sessionID: String,
        timestamp: Date = Date(),
        kind: AgentObservationKind,
        title: String? = nil,
        message: String? = nil,
        workspacePath: String? = nil,
        rawSource: String? = nil,
        severity: DiagnosticSeverity = .info,
        traceID: String = UUID().uuidString,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.provider = provider
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.message = message
        self.workspacePath = workspacePath
        self.rawSource = rawSource
        self.severity = severity
        self.traceID = traceID
        self.metadata = metadata
    }
}

public struct CollectorHealthSnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: AgentProvider
    public var provider: AgentProvider
    public var isRunning: Bool
    public var lastEventAt: Date?
    public var lastSuccessAt: Date?
    public var lastError: String?
    public var trackedSourceCount: Int
    public var droppedEventCount: Int

    public init(
        provider: AgentProvider,
        isRunning: Bool = false,
        lastEventAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil,
        trackedSourceCount: Int = 0,
        droppedEventCount: Int = 0
    ) {
        self.id = provider
        self.provider = provider
        self.isRunning = isRunning
        self.lastEventAt = lastEventAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.trackedSourceCount = trackedSourceCount
        self.droppedEventCount = droppedEventCount
    }
}

public struct DiagnosticEvent: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let traceID: String
    public let subsystem: String
    public let severity: DiagnosticSeverity
    public let message: String
    public let metadata: [String: String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        traceID: String = UUID().uuidString,
        subsystem: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.traceID = traceID
        self.subsystem = subsystem
        self.severity = severity
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct ReplayBundle: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let bundleID: String
    public let createdAt: Date
    public let provider: AgentProvider?
    public let rawEventsFile: URL
    public let snapshotsFile: URL
    public let diagnosticsFile: URL
    public let appContextFile: URL

    public init(
        id: UUID = UUID(),
        bundleID: String,
        createdAt: Date = Date(),
        provider: AgentProvider?,
        rawEventsFile: URL,
        snapshotsFile: URL,
        diagnosticsFile: URL,
        appContextFile: URL
    ) {
        self.id = id
        self.bundleID = bundleID
        self.createdAt = createdAt
        self.provider = provider
        self.rawEventsFile = rawEventsFile
        self.snapshotsFile = snapshotsFile
        self.diagnosticsFile = diagnosticsFile
        self.appContextFile = appContextFile
    }
}

public struct PermissionRequestSnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var provider: AgentProvider
    public var sessionID: String
    public var toolName: String
    public var summary: String
    public var createdAt: Date
    public var source: String
    public var isResolved: Bool

    public init(
        id: UUID = UUID(),
        provider: AgentProvider,
        sessionID: String,
        toolName: String,
        summary: String,
        createdAt: Date = Date(),
        source: String,
        isResolved: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.sessionID = sessionID
        self.toolName = toolName
        self.summary = summary
        self.createdAt = createdAt
        self.source = source
        self.isResolved = isResolved
    }
}

public struct AgentRuntimeSnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public var provider: AgentProvider
    public var sessionID: String
    public var workspacePath: String?
    public var taskTitle: String
    public var latestProgressText: String
    public var rawPhase: AgentRawPhase
    public var needsPermission: Bool
    public var needsInput: Bool
    public var isWorking: Bool
    public var isFinished: Bool
    public var isFailed: Bool
    public var startedAt: Date
    public var lastUpdatedAt: Date
    public var stateEnteredAt: Date
    public var quotaStatus: AgentQuotaStatus
    public var providerMeta: [String: String]
    public var lastTraceID: String

    public init(
        provider: AgentProvider,
        sessionID: String,
        workspacePath: String? = nil,
        taskTitle: String,
        latestProgressText: String = "",
        rawPhase: AgentRawPhase = .booting,
        needsPermission: Bool = false,
        needsInput: Bool = false,
        isWorking: Bool = false,
        isFinished: Bool = false,
        isFailed: Bool = false,
        startedAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        stateEnteredAt: Date = Date(),
        quotaStatus: AgentQuotaStatus = .unknown,
        providerMeta: [String: String] = [:],
        lastTraceID: String = UUID().uuidString
    ) {
        self.id = "\(provider.rawValue):\(sessionID)"
        self.provider = provider
        self.sessionID = sessionID
        self.workspacePath = workspacePath
        self.taskTitle = taskTitle
        self.latestProgressText = latestProgressText
        self.rawPhase = rawPhase
        self.needsPermission = needsPermission
        self.needsInput = needsInput
        self.isWorking = isWorking
        self.isFinished = isFinished
        self.isFailed = isFailed
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.stateEnteredAt = stateEnteredAt
        self.quotaStatus = quotaStatus
        self.providerMeta = providerMeta
        self.lastTraceID = lastTraceID
    }
}

public struct TaskCardSnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public var provider: AgentProvider
    public var title: String
    public var boardState: BoardState
    public var progressText: String
    public var elapsedSeconds: Int
    public var isSelected: Bool

    public init(
        id: String,
        provider: AgentProvider,
        title: String,
        boardState: BoardState,
        progressText: String,
        elapsedSeconds: Int,
        isSelected: Bool
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.boardState = boardState
        self.progressText = progressText
        self.elapsedSeconds = elapsedSeconds
        self.isSelected = isSelected
    }
}

public struct ProviderSummarySnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: AgentProvider
    public var provider: AgentProvider
    public var activeTaskCount: Int
    public var waitingInputCount: Int
    public var waitingApprovalCount: Int
    public var errorCount: Int
    public var quotaStatus: AgentQuotaStatus

    public init(
        provider: AgentProvider,
        activeTaskCount: Int = 0,
        waitingInputCount: Int = 0,
        waitingApprovalCount: Int = 0,
        errorCount: Int = 0,
        quotaStatus: AgentQuotaStatus = .unknown
    ) {
        self.id = provider
        self.provider = provider
        self.activeTaskCount = activeTaskCount
        self.waitingInputCount = waitingInputCount
        self.waitingApprovalCount = waitingApprovalCount
        self.errorCount = errorCount
        self.quotaStatus = quotaStatus
    }
}

public struct TaskBoardSelectionState: Sendable, Equatable, Codable {
    public var selectedCardID: String?
    public var isGlobalBrowseMode: Bool

    public init(selectedCardID: String? = nil, isGlobalBrowseMode: Bool = false) {
        self.selectedCardID = selectedCardID
        self.isGlobalBrowseMode = isGlobalBrowseMode
    }
}

public struct TaskBoardSnapshot: Sendable, Equatable, Codable {
    public var boardType: String
    public var cards: [TaskCardSnapshot]
    public var hiddenCount: Int
    public var selectedCardID: String?
    public var isGlobalBrowseMode: Bool
    public var layoutMode: TaskBoardLayoutMode
    public var providerSummaries: [ProviderSummarySnapshot]
    public var generatedAt: Date

    public init(
        boardType: String = "multiTask",
        cards: [TaskCardSnapshot],
        hiddenCount: Int,
        selectedCardID: String?,
        isGlobalBrowseMode: Bool,
        layoutMode: TaskBoardLayoutMode,
        providerSummaries: [ProviderSummarySnapshot],
        generatedAt: Date = Date()
    ) {
        self.boardType = boardType
        self.cards = cards
        self.hiddenCount = hiddenCount
        self.selectedCardID = selectedCardID
        self.isGlobalBrowseMode = isGlobalBrowseMode
        self.layoutMode = layoutMode
        self.providerSummaries = providerSummaries
        self.generatedAt = generatedAt
    }
}

public struct AudioWaveformSnapshot: Sendable, Equatable, Codable {
    public var levelBars: [UInt8]
    public var peak: UInt8
    public var recordingState: String
    public var subtitle: String
    public var capturedAt: Date

    public init(
        levelBars: [UInt8] = [],
        peak: UInt8 = 0,
        recordingState: String = "",
        subtitle: String = "",
        capturedAt: Date = Date()
    ) {
        self.levelBars = levelBars
        self.peak = peak
        self.recordingState = recordingState
        self.subtitle = subtitle
        self.capturedAt = capturedAt
    }
}

public struct EmbeddedDisplaySnapshot: Sendable, Equatable, Codable {
    public var sequence: UInt64
    public var mode: EmbeddedDisplayMode
    public var taskBoard: TaskBoardSnapshot?
    public var waveform: AudioWaveformSnapshot?
    public var generatedAt: Date

    public init(
        sequence: UInt64,
        mode: EmbeddedDisplayMode,
        taskBoard: TaskBoardSnapshot? = nil,
        waveform: AudioWaveformSnapshot? = nil,
        generatedAt: Date = Date()
    ) {
        self.sequence = sequence
        self.mode = mode
        self.taskBoard = taskBoard
        self.waveform = waveform
        self.generatedAt = generatedAt
    }
}

public struct EmbeddedBoardDeviceInfo: Sendable, Equatable, Codable {
    public var deviceID: String
    public var firmwareVersion: String
    public var protocolVersion: Int
    public var screenWidth: Int
    public var screenHeight: Int
    public var maxPayloadBytes: Int
    public var transportKind: EmbeddedTransportKind
    public var supportsInputReturn: Bool
    public var supportsCompression: Bool

    public init(
        deviceID: String,
        firmwareVersion: String,
        protocolVersion: Int = 1,
        screenWidth: Int = 0,
        screenHeight: Int = 0,
        maxPayloadBytes: Int = 64,
        transportKind: EmbeddedTransportKind = .unknown,
        supportsInputReturn: Bool = false,
        supportsCompression: Bool = false
    ) {
        self.deviceID = deviceID
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.maxPayloadBytes = maxPayloadBytes
        self.transportKind = transportKind
        self.supportsInputReturn = supportsInputReturn
        self.supportsCompression = supportsCompression
    }
}

public struct DeviceStatusSnapshot: Sendable, Equatable, Codable {
    public var renderFPS: Double
    public var freeHeapBytes: Int
    public var lastSequenceRendered: UInt64
    public var frameDropCount: Int
    public var decodeErrorCount: Int
    public var uptimeSeconds: Int

    public init(
        renderFPS: Double = 0,
        freeHeapBytes: Int = 0,
        lastSequenceRendered: UInt64 = 0,
        frameDropCount: Int = 0,
        decodeErrorCount: Int = 0,
        uptimeSeconds: Int = 0
    ) {
        self.renderFPS = renderFPS
        self.freeHeapBytes = freeHeapBytes
        self.lastSequenceRendered = lastSequenceRendered
        self.frameDropCount = frameDropCount
        self.decodeErrorCount = decodeErrorCount
        self.uptimeSeconds = uptimeSeconds
    }
}

public struct EmbeddedBoardConnectionState: Sendable, Equatable, Codable {
    public var phase: EmbeddedBoardConnectionPhase
    public var deviceInfo: EmbeddedBoardDeviceInfo?
    public var reason: String?
    public var updatedAt: Date

    public init(
        phase: EmbeddedBoardConnectionPhase,
        deviceInfo: EmbeddedBoardDeviceInfo? = nil,
        reason: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.phase = phase
        self.deviceInfo = deviceInfo
        self.reason = reason
        self.updatedAt = updatedAt
    }

    public static var disconnected: EmbeddedBoardConnectionState {
        EmbeddedBoardConnectionState(phase: .disconnected)
    }
}

public enum EmbeddedBoardInboundEvent: Sendable, Equatable {
    case helloAck(EmbeddedBoardDeviceInfo)
    case ack(sequence: UInt64)
    case nack(sequence: UInt64, code: String)
    case deviceStatus(DeviceStatusSnapshot)
    case input(EmbeddedBoardInputEventKind)
    case pong
}

public struct EmbeddedBoardPacketFrame: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var kind: EmbeddedBoardPacketKind
    public var sequence: UInt64
    public var chunkIndex: Int
    public var chunkCount: Int
    public var payload: Data
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: EmbeddedBoardPacketKind,
        sequence: UInt64,
        chunkIndex: Int = 0,
        chunkCount: Int = 1,
        payload: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sequence = sequence
        self.chunkIndex = chunkIndex
        self.chunkCount = chunkCount
        self.payload = payload
        self.createdAt = createdAt
    }
}

public protocol AgentCollector: Sendable {
    var provider: AgentProvider { get }
    var events: AsyncStream<AgentObservationEvent> { get }

    func start() async
    func stop() async
    func healthSnapshot() async -> CollectorHealthSnapshot
    func replay(from bundle: ReplayBundle) async throws -> [AgentObservationEvent]
    func debugSummary() async -> String
}

public protocol AgentStateReducing: Sendable {
    func reduce(
        event: AgentObservationEvent,
        current: AgentRuntimeSnapshot?
    ) -> (snapshot: AgentRuntimeSnapshot?, permissionUpdate: PermissionRequestSnapshot?)

    func inferBoardState(snapshot: AgentRuntimeSnapshot) -> BoardState
    func refreshedSnapshots(
        from snapshots: [AgentRuntimeSnapshot],
        at now: Date
    ) -> [AgentRuntimeSnapshot]
}

public protocol TaskBoardSnapshotBuilding: Sendable {
    func makeSnapshot(
        from runtimeSnapshots: [AgentRuntimeSnapshot],
        selection: TaskBoardSelectionState,
        generatedAt: Date
    ) -> TaskBoardSnapshot
}

public protocol EmbeddedDisplaySnapshotBuilding: Sendable {
    func makeSnapshot(
        sequence: UInt64,
        mode: EmbeddedDisplayMode,
        taskBoard: TaskBoardSnapshot?,
        waveform: AudioWaveformSnapshot?,
        generatedAt: Date
    ) -> EmbeddedDisplaySnapshot
}

public protocol EmbeddedDisplayEncoding: Sendable {
    func makeFrames(
        for snapshot: EmbeddedDisplaySnapshot,
        mtu: Int?
    ) throws -> [EmbeddedBoardPacketFrame]

    func digest(for snapshot: EmbeddedDisplaySnapshot) throws -> Data
}

public protocol EmbeddedBoardTransport: Sendable {
    var inboundEvents: AsyncStream<EmbeddedBoardInboundEvent> { get }
    var connectionStates: AsyncStream<EmbeddedBoardConnectionState> { get }
    var supportsFragmentation: Bool { get }
    var supportsBidirectionalEvents: Bool { get }

    func start() async
    func stop() async
    func send(_ frame: EmbeddedBoardPacketFrame) async throws
}

public enum AgentMonitorPaths {
    public static func baseDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("SlashVibe", isDirectory: true)
            .appendingPathComponent("AgentMonitor", isDirectory: true)
    }

    public static func hooksDirectory(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager).appendingPathComponent("hooks", isDirectory: true)
    }

    public static func eventsDirectory(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager).appendingPathComponent("events", isDirectory: true)
    }

    public static func stateDirectory(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager).appendingPathComponent("state", isDirectory: true)
    }

    public static func diagnosticsDirectory(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager).appendingPathComponent("diagnostics", isDirectory: true)
    }

    public static func replayDirectory(fileManager: FileManager = .default) -> URL {
        baseDirectory(fileManager: fileManager).appendingPathComponent("replay", isDirectory: true)
    }
}
