import Foundation
import SpeechBarDomain

private struct HookInboxEnvelope: Decodable {
    var sessionID: String?
    var kind: String?
    var title: String?
    var message: String?
    var workspacePath: String?
    var timestamp: Date?
    var metadata: [String: String]?
    var severity: String?
}

private struct CollectorStats {
    var isRunning = false
    var lastEventAt: Date?
    var lastSuccessAt: Date?
    var lastError: String?
    var trackedSourceCount = 0
    var droppedEventCount = 0
}

open class HookInboxCollector: AgentCollector, @unchecked Sendable {
    public let provider: AgentProvider
    public let events: AsyncStream<AgentObservationEvent>

    private let continuation: AsyncStream<AgentObservationEvent>.Continuation
    private let fileManager: FileManager
    private let pollInterval: Duration
    private let inboxDirectory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var readers: [URL: IncrementalTextFileReader] = [:]
    private var pollTask: Task<Void, Never>?
    private let stateQueue: DispatchQueue
    private var stats = CollectorStats()

    public init(
        provider: AgentProvider,
        inboxDirectory: URL,
        pollInterval: Duration = .seconds(2),
        fileManager: FileManager = .default
    ) {
        self.provider = provider
        self.inboxDirectory = inboxDirectory
        self.pollInterval = pollInterval
        self.fileManager = fileManager
        self.stateQueue = DispatchQueue(label: "com.startup.speechbar.collector.\(provider.rawValue)")
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601
        var capturedContinuation: AsyncStream<AgentObservationEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    public func start() async {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard pollTask == nil else { return false }
            stats.isRunning = true
            stats.lastError = nil
            return true
        }
        guard shouldStart else { return }

        pollTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    public func stop() async {
        let task = stateQueue.sync { () -> Task<Void, Never>? in
            stats.isRunning = false
            let task = pollTask
            pollTask = nil
            return task
        }
        task?.cancel()
    }

    public func healthSnapshot() async -> CollectorHealthSnapshot {
        stateQueue.sync {
            CollectorHealthSnapshot(
                provider: provider,
                isRunning: stats.isRunning,
                lastEventAt: stats.lastEventAt,
                lastSuccessAt: stats.lastSuccessAt,
                lastError: stats.lastError,
                trackedSourceCount: stats.trackedSourceCount,
                droppedEventCount: stats.droppedEventCount
            )
        }
    }

    public func replay(from bundle: ReplayBundle) async throws -> [AgentObservationEvent] {
        let data = try Data(contentsOf: bundle.rawEventsFile)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.compactMap { line in
            let event = try decoder.decode(AgentObservationEvent.self, from: Data(line.utf8))
            return event.provider == provider ? event : nil
        }
    }

    public func debugSummary() async -> String {
        let health = await healthSnapshot()
        return "\(provider.displayName): running=\(health.isRunning) tracked=\(health.trackedSourceCount) dropped=\(health.droppedEventCount)"
    }

    func pollOnce() async {
        do {
            try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true, attributes: nil)
            let files = try fileManager.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { $0.pathExtension == "jsonl" || $0.pathExtension == "log" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            stateQueue.sync {
                stats.trackedSourceCount = files.count
            }

            for fileURL in files {
                try await process(fileURL: fileURL)
            }

            stateQueue.sync {
                stats.lastSuccessAt = Date()
            }
        } catch {
            stateQueue.sync {
                stats.lastError = error.localizedDescription
            }
            continuation.yield(
                AgentObservationEvent(
                    provider: provider,
                    sessionID: "collector",
                    kind: .collectorError,
                    message: error.localizedDescription,
                    rawSource: inboxDirectory.path,
                    severity: .warning
                )
            )
        }
    }

    private func process(fileURL: URL) async throws {
        var reader = readers[fileURL] ?? IncrementalTextFileReader()
        let lines = try reader.readNewLines(from: fileURL, fileManager: fileManager)
        readers[fileURL] = reader

        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let envelope = try decoder.decode(HookInboxEnvelope.self, from: data)
                let kind = envelope.kind.flatMap(AgentObservationKind.init(rawValue:)) ?? .agentOutput
                let sessionID = envelope.sessionID ?? fileURL.deletingPathExtension().lastPathComponent
                let severity = envelope.severity.flatMap(DiagnosticSeverityLabel.init(rawValue:))?.value ?? .info
                let event = AgentObservationEvent(
                    provider: provider,
                    sessionID: sessionID,
                    timestamp: envelope.timestamp ?? Date(),
                    kind: kind,
                    title: envelope.title,
                    message: envelope.message,
                    workspacePath: envelope.workspacePath,
                    rawSource: fileURL.path,
                    severity: severity,
                    metadata: envelope.metadata ?? [:]
                )
                stateQueue.sync {
                    stats.lastEventAt = event.timestamp
                }
                continuation.yield(event)
            } catch {
                stateQueue.sync {
                    stats.droppedEventCount += 1
                    stats.lastError = "Failed to parse hook event from \(fileURL.lastPathComponent)"
                }
            }
        }
    }
}

public final class ClaudeHookCollector: HookInboxCollector, @unchecked Sendable {
    public init(
        baseDirectory: URL = AgentMonitorPaths.hooksDirectory().appendingPathComponent("claude-code", isDirectory: true),
        pollInterval: Duration = .seconds(2),
        fileManager: FileManager = .default
    ) {
        super.init(provider: .claudeCode, inboxDirectory: baseDirectory, pollInterval: pollInterval, fileManager: fileManager)
    }
}

public final class GeminiHookCollector: HookInboxCollector, @unchecked Sendable {
    public init(
        baseDirectory: URL = AgentMonitorPaths.hooksDirectory().appendingPathComponent("gemini-cli", isDirectory: true),
        pollInterval: Duration = .seconds(2),
        fileManager: FileManager = .default
    ) {
        super.init(provider: .geminiCLI, inboxDirectory: baseDirectory, pollInterval: pollInterval, fileManager: fileManager)
    }
}

public final class CursorHookCollector: HookInboxCollector, @unchecked Sendable {
    public init(
        baseDirectory: URL = AgentMonitorPaths.hooksDirectory().appendingPathComponent("cursor-agent", isDirectory: true),
        pollInterval: Duration = .seconds(2),
        fileManager: FileManager = .default
    ) {
        super.init(provider: .cursorAgent, inboxDirectory: baseDirectory, pollInterval: pollInterval, fileManager: fileManager)
    }
}

private enum DiagnosticSeverityLabel: String {
    case info
    case warning
    case error
    case critical

    var value: DiagnosticSeverity {
        switch self {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        case .critical:
            return .critical
        }
    }
}

struct CodexTrackedFile: Sendable {
    var reader: IncrementalTextFileReader
    var sessionID: String
    var workspacePath: String
    var lastEventAt: Date
    var lastObservedState: AgentRawPhase?
    var hadToolUse: Bool
    var pendingApproval: PendingApproval?
}

struct PendingApproval: Sendable {
    var expiresAt: Date
    var command: String
}

public final class CodexJSONLCollector: AgentCollector, @unchecked Sendable {
    public let provider: AgentProvider = .codexCLI
    public let events: AsyncStream<AgentObservationEvent>

    private let continuation: AsyncStream<AgentObservationEvent>.Continuation
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let pollInterval: Duration
    private let sessionLookbackDays: Int
    private let activeFileThreshold: TimeInterval
    private let staleSessionThreshold: TimeInterval
    private let approvalHeuristicThreshold: TimeInterval
    private let maxTrackedFiles: Int
    private let decoder = JSONDecoder()
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.collector.codex")
    private var stats = CollectorStats()
    private var trackedFiles: [URL: CodexTrackedFile] = [:]
    private var pollTask: Task<Void, Never>?

    public init(
        baseDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions", isDirectory: true),
        pollInterval: Duration = .milliseconds(1500),
        sessionLookbackDays: Int = 3,
        activeFileThreshold: TimeInterval = 120,
        staleSessionThreshold: TimeInterval = 600,
        approvalHeuristicThreshold: TimeInterval = 2,
        maxTrackedFiles: Int = 50,
        fileManager: FileManager = .default
    ) {
        self.baseDirectory = baseDirectory
        self.pollInterval = pollInterval
        self.sessionLookbackDays = sessionLookbackDays
        self.activeFileThreshold = activeFileThreshold
        self.staleSessionThreshold = staleSessionThreshold
        self.approvalHeuristicThreshold = approvalHeuristicThreshold
        self.maxTrackedFiles = maxTrackedFiles
        self.fileManager = fileManager
        var capturedContinuation: AsyncStream<AgentObservationEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    public func start() async {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard pollTask == nil else { return false }
            stats.isRunning = true
            stats.lastError = nil
            return true
        }
        guard shouldStart else { return }

        pollTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce(now: Date())
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    public func stop() async {
        let task = stateQueue.sync { () -> Task<Void, Never>? in
            stats.isRunning = false
            let task = pollTask
            pollTask = nil
            return task
        }
        task?.cancel()
    }

    public func healthSnapshot() async -> CollectorHealthSnapshot {
        stateQueue.sync {
            CollectorHealthSnapshot(
                provider: provider,
                isRunning: stats.isRunning,
                lastEventAt: stats.lastEventAt,
                lastSuccessAt: stats.lastSuccessAt,
                lastError: stats.lastError,
                trackedSourceCount: stats.trackedSourceCount,
                droppedEventCount: stats.droppedEventCount
            )
        }
    }

    public func replay(from bundle: ReplayBundle) async throws -> [AgentObservationEvent] {
        let data = try Data(contentsOf: bundle.rawEventsFile)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.compactMap { line in
            let event = try decoder.decode(AgentObservationEvent.self, from: Data(line.utf8))
            return event.provider == .codexCLI ? event : nil
        }
    }

    public func debugSummary() async -> String {
        let health = await healthSnapshot()
        return "Codex: running=\(health.isRunning) tracked=\(health.trackedSourceCount) dropped=\(health.droppedEventCount) base=\(baseDirectory.path)"
    }

    @discardableResult
    func pollOnce(now: Date) async -> [AgentObservationEvent] {
        var emittedEvents: [AgentObservationEvent] = []
        do {
            let candidateFiles = try discoverCandidateFiles(now: now)
            stateQueue.sync {
                stats.trackedSourceCount = candidateFiles.count
            }
            for fileURL in candidateFiles {
                emittedEvents.append(contentsOf: try await process(fileURL: fileURL, now: now))
            }
            emittedEvents.append(contentsOf: resolvePendingApprovals(now: now))
            cleanupStaleSessions(now: now)
            stateQueue.sync {
                stats.lastSuccessAt = now
            }
        } catch {
            stateQueue.sync {
                stats.lastError = error.localizedDescription
            }
            continuation.yield(
                AgentObservationEvent(
                    provider: .codexCLI,
                    sessionID: "collector",
                    timestamp: now,
                    kind: .collectorError,
                    message: error.localizedDescription,
                    workspacePath: nil,
                    rawSource: baseDirectory.path,
                    severity: .warning
                )
            )
            emittedEvents.append(
                AgentObservationEvent(
                    provider: .codexCLI,
                    sessionID: "collector",
                    timestamp: now,
                    kind: .collectorError,
                    message: error.localizedDescription,
                    workspacePath: nil,
                    rawSource: baseDirectory.path,
                    severity: .warning
                )
            )
        }
        return emittedEvents
    }

    private func discoverCandidateFiles(now: Date) throws -> [URL] {
        var candidates: [URL] = []
        let calendar = Calendar(identifier: .gregorian)
        for offset in 0..<sessionLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let directory = baseDirectory
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)

            guard fileManager.fileExists(atPath: directory.path) else { continue }
            let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
            for url in urls where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedAt = values.contentModificationDate ?? .distantPast
                if trackedFiles[url] != nil || now.timeIntervalSince(modifiedAt) <= activeFileThreshold {
                    candidates.append(url)
                }
            }
        }
        return Array(candidates.sorted(by: { $0.path < $1.path }).prefix(maxTrackedFiles))
    }

    private func process(fileURL: URL, now: Date) async throws -> [AgentObservationEvent] {
        var tracked = trackedFiles[fileURL] ?? CodexTrackedFile(
            reader: IncrementalTextFileReader(),
            sessionID: "codex:" + extractSessionID(from: fileURL.lastPathComponent),
            workspacePath: "",
            lastEventAt: now,
            lastObservedState: nil,
            hadToolUse: false,
            pendingApproval: nil
        )

        let lines = try tracked.reader.readNewLines(from: fileURL, fileManager: fileManager)
        trackedFiles[fileURL] = tracked
        var emittedEvents: [AgentObservationEvent] = []

        for line in lines {
            if let event = decodeCodexEvent(from: line, tracked: &tracked, now: now, sourcePath: fileURL.path) {
                stateQueue.sync {
                    stats.lastEventAt = event.timestamp
                }
                continuation.yield(event)
                emittedEvents.append(event)
            }
        }

        trackedFiles[fileURL] = tracked
        return emittedEvents
    }

    private func decodeCodexEvent(
        from line: String,
        tracked: inout CodexTrackedFile,
        now: Date,
        sourcePath: String
    ) -> AgentObservationEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = root["type"] as? String
        else {
            stateQueue.sync {
                stats.droppedEventCount += 1
            }
            return nil
        }

        let payload = root["payload"] as? [String: Any]
        let payloadType = payload?["type"] as? String
        let key = payloadType.map { "\(type):\($0)" } ?? type

        if type == "session_meta" {
            tracked.workspacePath = payload?["cwd"] as? String ?? tracked.workspacePath
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .sessionStarted,
                title: tracked.workspacePath.split(separator: "/").last.map(String.init),
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        }

        switch key {
        case "event_msg:task_started":
            tracked.hadToolUse = false
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .taskStarted,
                title: payload?["title"] as? String,
                message: "开始执行任务",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "event_msg:user_message":
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .agentOutput,
                title: payload?["title"] as? String,
                message: "收到新的用户输入",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "event_msg:agent_message":
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .agentOutput,
                title: payload?["title"] as? String,
                message: payload?["text"] as? String ?? "处理中",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "response_item:function_call", "response_item:custom_tool_call", "response_item:web_search_call":
            tracked.hadToolUse = true
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            if let command = extractCommand(from: payload) {
                tracked.pendingApproval = PendingApproval(
                    expiresAt: now.addingTimeInterval(approvalHeuristicThreshold),
                    command: command
                )
            }
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .toolStarted,
                title: payload?["name"] as? String,
                message: payload?["name"] as? String ?? "工具调用中",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "response_item:function_call_output", "event_msg:exec_command_end":
            tracked.pendingApproval = nil
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .toolFinished,
                message: "工具调用完成",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "event_msg:task_complete":
            tracked.pendingApproval = nil
            tracked.lastObservedState = .finished
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .taskFinished,
                message: tracked.hadToolUse ? "任务完成" : "会话结束",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        case "event_msg:turn_aborted":
            tracked.pendingApproval = nil
            tracked.lastObservedState = .failed
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .taskFailed,
                message: "任务已中止",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath,
                severity: .warning
            )
        case "event_msg:context_compacted":
            tracked.lastObservedState = .running
            tracked.lastEventAt = now
            return AgentObservationEvent(
                provider: .codexCLI,
                sessionID: tracked.sessionID,
                timestamp: now,
                kind: .agentOutput,
                message: "上下文已压缩",
                workspacePath: tracked.workspacePath,
                rawSource: sourcePath
            )
        default:
            return nil
        }
    }

    private func resolvePendingApprovals(now: Date) -> [AgentObservationEvent] {
        let current = trackedFiles
        var emittedEvents: [AgentObservationEvent] = []
        for (url, tracked) in current {
            guard let pendingApproval = tracked.pendingApproval, now >= pendingApproval.expiresAt else {
                continue
            }
            var updated = tracked
            updated.pendingApproval = nil
            updated.lastObservedState = .waitingApproval
            updated.lastEventAt = now
            trackedFiles[url] = updated
            let event = AgentObservationEvent(
                provider: .codexCLI,
                sessionID: updated.sessionID,
                timestamp: now,
                kind: .waitingApproval,
                message: pendingApproval.command,
                workspacePath: updated.workspacePath,
                rawSource: url.path,
                metadata: ["toolName": "shell_command"]
            )
            continuation.yield(event)
            emittedEvents.append(event)
        }
        return emittedEvents
    }

    private func cleanupStaleSessions(now: Date) {
        let staleURLs = trackedFiles.compactMap { url, tracked -> URL? in
            now.timeIntervalSince(tracked.lastEventAt) >= staleSessionThreshold ? url : nil
        }
        for url in staleURLs {
            trackedFiles.removeValue(forKey: url)
        }
    }

    private func extractSessionID(from filename: String) -> String {
        let base = filename.replacingOccurrences(of: ".jsonl", with: "")
        let components = base.split(separator: "-")
        guard components.count >= 6 else { return UUID().uuidString }
        return components.suffix(5).joined(separator: "-")
    }

    private func extractCommand(from payload: [String: Any]?) -> String? {
        guard
            let payload,
            payload["name"] as? String == "shell_command"
        else {
            return nil
        }

        if let arguments = payload["arguments"] as? String,
           let data = arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let command = object["command"] as? String {
            return command
        }

        if let arguments = payload["arguments"] as? [String: Any],
           let command = arguments["command"] as? String {
            return command
        }

        return nil
    }
}
