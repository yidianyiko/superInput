import Foundation

public enum SensitivityClass: String, Sendable, Codable, Equatable {
    case normal
    case redacted
    case secureExcluded
    case optOut
}

public enum ObservationStatus: String, Sendable, Codable, Equatable {
    case observedFinal
    case observedNoChange
    case unavailable
    case blockedSensitive
}

public enum MemoryActionType: String, Sendable, Codable, Equatable {
    case transcribe
    case polish
    case commentFill
    case textFill
    case formFill
}

public enum InputEventSource: String, Sendable, Codable, Equatable {
    case speech
    case manualTrigger
    case directFill
}

public enum InputEventOutcome: String, Sendable, Codable, Equatable {
    case published
    case failed
    case skippedSensitive
}

public enum RecallCapability: String, Sendable, Codable, Equatable {
    case transcription
    case polish
    case directFill
}

public enum MemoryType: String, Sendable, Codable, Equatable, CaseIterable {
    case vocabulary
    case correction
    case style
    case scene
}

public enum MemoryScope: Sendable, Codable, Equatable {
    case global
    case app(String)
    case window(appIdentifier: String, windowTitle: String)
    case field(appIdentifier: String, windowTitle: String?, fieldRole: String, fieldLabel: String?)

    public var specificityRank: Int {
        switch self {
        case .global:
            return 0
        case .app:
            return 1
        case .window:
            return 2
        case .field:
            return 3
        }
    }

    public var identityComponent: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(self) else {
            return "\(specificityRank)"
        }
        return encoded.base64EncodedString()
    }
}

public enum MemoryStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case active
    case hidden
    case deleted
}

public struct InputEvent: Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let languageCode: String
    public let localeIdentifier: String
    public let appIdentifier: String
    public let appName: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let sensitivityClass: SensitivityClass
    public let observationStatus: ObservationStatus
    public let actionType: MemoryActionType
    public let rawTranscript: String?
    public let polishedText: String?
    public let insertedText: String?
    public let finalUserEditedText: String?
    public let outcome: InputEventOutcome
    public let durationMs: Int
    public let source: InputEventSource

    public init(
        id: UUID,
        timestamp: Date,
        languageCode: String,
        localeIdentifier: String,
        appIdentifier: String,
        appName: String,
        windowTitle: String?,
        pageTitle: String?,
        fieldRole: String,
        fieldLabel: String?,
        sensitivityClass: SensitivityClass,
        observationStatus: ObservationStatus,
        actionType: MemoryActionType,
        rawTranscript: String?,
        polishedText: String?,
        insertedText: String?,
        finalUserEditedText: String?,
        outcome: InputEventOutcome,
        durationMs: Int,
        source: InputEventSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.languageCode = languageCode
        self.localeIdentifier = localeIdentifier
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.pageTitle = pageTitle
        self.fieldRole = fieldRole
        self.fieldLabel = fieldLabel
        self.sensitivityClass = sensitivityClass
        self.observationStatus = observationStatus
        self.actionType = actionType
        self.rawTranscript = rawTranscript
        self.polishedText = polishedText
        self.insertedText = insertedText
        self.finalUserEditedText = finalUserEditedText
        self.outcome = outcome
        self.durationMs = durationMs
        self.source = source
    }

    public var hasConfirmedFinalText: Bool {
        observationStatus == .observedFinal || observationStatus == .observedNoChange
    }

    public var isProvisional: Bool {
        observationStatus == .unavailable
    }

    public var effectiveLearningText: String? {
        if let finalUserEditedText, hasConfirmedFinalText {
            return finalUserEditedText
        }
        return insertedText ?? polishedText ?? rawTranscript
    }
}

public struct MemoryItem: Sendable, Codable, Equatable {
    public let id: UUID
    public let type: MemoryType
    public let key: String
    public let valuePayload: Data
    public let valueFingerprint: String
    public let identityHash: String
    public let scope: MemoryScope
    public let confidence: Double
    public let status: MemoryStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let lastConfirmedAt: Date?
    public let sourceEventIDs: [UUID]

    public init(
        id: UUID,
        type: MemoryType,
        key: String,
        valuePayload: Data,
        valueFingerprint: String,
        identityHash: String,
        scope: MemoryScope,
        confidence: Double,
        status: MemoryStatus,
        createdAt: Date,
        updatedAt: Date,
        lastConfirmedAt: Date?,
        sourceEventIDs: [UUID]
    ) {
        self.id = id
        self.type = type
        self.key = key
        self.valuePayload = valuePayload
        self.valueFingerprint = valueFingerprint
        self.identityHash = identityHash
        self.scope = scope
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConfirmedAt = lastConfirmedAt
        self.sourceEventIDs = sourceEventIDs
    }
}

public struct RecallRequest: Sendable, Equatable {
    public let timestamp: Date
    public let appIdentifier: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let requestedCapabilities: [RecallCapability]

    public init(
        timestamp: Date,
        appIdentifier: String,
        windowTitle: String?,
        pageTitle: String?,
        fieldRole: String,
        fieldLabel: String?,
        requestedCapabilities: [RecallCapability]
    ) {
        self.timestamp = timestamp
        self.appIdentifier = appIdentifier
        self.windowTitle = windowTitle
        self.pageTitle = pageTitle
        self.fieldRole = fieldRole
        self.fieldLabel = fieldLabel
        self.requestedCapabilities = requestedCapabilities
    }
}

public struct RecallBundle: Sendable, Equatable {
    public let vocabularyHints: [String]
    public let correctionHints: [String]
    public let styleHints: [String]
    public let sceneHints: [String]
    public let diagnosticSummary: String

    public init(
        vocabularyHints: [String],
        correctionHints: [String],
        styleHints: [String],
        sceneHints: [String],
        diagnosticSummary: String
    ) {
        self.vocabularyHints = vocabularyHints
        self.correctionHints = correctionHints
        self.styleHints = styleHints
        self.sceneHints = sceneHints
        self.diagnosticSummary = diagnosticSummary
    }
}

public struct FocusedInputSnapshot: Sendable, Equatable {
    public let appIdentifier: String
    public let appName: String
    public let windowTitle: String?
    public let pageTitle: String?
    public let fieldRole: String
    public let fieldLabel: String?
    public let isEditable: Bool
    public let isSecure: Bool

    public init(
        appIdentifier: String,
        appName: String,
        windowTitle: String?,
        pageTitle: String?,
        fieldRole: String,
        fieldLabel: String?,
        isEditable: Bool,
        isSecure: Bool
    ) {
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.pageTitle = pageTitle
        self.fieldRole = fieldRole
        self.fieldLabel = fieldLabel
        self.isEditable = isEditable
        self.isSecure = isSecure
    }
}

public struct SensitiveFieldClassifier: Sendable {
    public let optedOutApps: Set<String>
    public let optedOutFieldLabels: Set<String>

    public init(optedOutApps: Set<String>, optedOutFieldLabels: Set<String>) {
        self.optedOutApps = optedOutApps
        self.optedOutFieldLabels = Set(optedOutFieldLabels.map { $0.lowercased() })
    }

    public func classify(_ snapshot: FocusedInputSnapshot) -> SensitivityClass {
        if snapshot.isSecure || looksSecure(role: snapshot.fieldRole, label: snapshot.fieldLabel) {
            return .secureExcluded
        }
        if optedOutApps.contains(snapshot.appIdentifier) {
            return .optOut
        }
        if let label = snapshot.fieldLabel?.lowercased(),
           optedOutFieldLabels.contains(label) {
            return .optOut
        }
        return .normal
    }

    private func looksSecure(role: String, label: String?) -> Bool {
        if role.lowercased().contains("secure") || role.lowercased().contains("password") {
            return true
        }

        guard let label = label?.lowercased() else {
            return false
        }

        let secureKeywords = [
            "password", "passcode", "one-time code", "verification code",
            "验证码", "密码", "口令", "token", "otp", "2fa"
        ]

        return secureKeywords.contains { label.contains($0) }
    }
}

public protocol MemoryStore: Sendable, MemoryCatalogProviding {
    func insert(event: InputEvent) async throws
    func upsert(memory: MemoryItem) async throws
    func listMemories(for request: RecallRequest) async throws -> [MemoryItem]
    func markDeleted(identityHash: String, deletedAt: Date) async throws
}

public protocol MemoryExtractor: Sendable {
    func extract(from event: InputEvent) async throws -> [MemoryItem]
}

public protocol MemoryRetriever: Sendable {
    func recall(for request: RecallRequest) async throws -> RecallBundle
}

public protocol MemoryEventRecording: Sendable {
    func record(event: InputEvent) async throws
}

public protocol FocusedInputSnapshotProviding: Sendable {
    func currentFocusedInputSnapshot() async -> FocusedInputSnapshot?
    func observedTextAfterPublish() async -> String?
}
