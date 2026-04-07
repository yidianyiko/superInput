import Combine
import Foundation
import SpeechBarDomain

private struct SnapshotRecord: Codable, Sendable {
    var createdAt: Date
    var runtimeSnapshots: [AgentRuntimeSnapshot]
    var taskBoardSnapshot: TaskBoardSnapshot?
    var embeddedDisplaySnapshot: EmbeddedDisplaySnapshot?
}

@MainActor
public final class DiagnosticsCoordinator: ObservableObject {
    @Published public private(set) var recentDiagnostics: [DiagnosticEvent] = []
    @Published public private(set) var recentBundles: [ReplayBundle] = []

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let maxRecentDiagnostics: Int
    private let maxRecentBundles: Int
    private let ioQueue = DispatchQueue(label: "com.startup.speechbar.agent-monitor.io", qos: .utility)
    private let currentRunID: String
    private let eventsFile: URL
    private let snapshotsFile: URL
    private let diagnosticsFile: URL
    private let contextFile: URL
    private let baseDirectory: URL

    public init(
        fileManager: FileManager = .default,
        baseDirectory: URL = AgentMonitorPaths.baseDirectory(),
        maxRecentDiagnostics: Int = 80,
        maxRecentBundles: Int = 20
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
        self.maxRecentDiagnostics = maxRecentDiagnostics
        self.maxRecentBundles = maxRecentBundles
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        let formatter = ISO8601DateFormatter()
        let currentRunID = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        self.currentRunID = currentRunID
        self.eventsFile = baseDirectory.appendingPathComponent("events", isDirectory: true).appendingPathComponent("\(currentRunID).jsonl")
        self.snapshotsFile = baseDirectory.appendingPathComponent("state", isDirectory: true).appendingPathComponent("\(currentRunID).jsonl")
        self.diagnosticsFile = baseDirectory.appendingPathComponent("diagnostics", isDirectory: true).appendingPathComponent("\(currentRunID).jsonl")
        self.contextFile = baseDirectory.appendingPathComponent("state", isDirectory: true).appendingPathComponent("\(currentRunID)-context.json")

        prepareDirectories()
    }

    public func recordObservation(_ event: AgentObservationEvent) {
        writeJSONLine(event, to: eventsFile)
    }

    public func recordSnapshots(
        runtimeSnapshots: [AgentRuntimeSnapshot],
        taskBoardSnapshot: TaskBoardSnapshot?,
        embeddedDisplaySnapshot: EmbeddedDisplaySnapshot?
    ) {
        let record = SnapshotRecord(
            createdAt: Date(),
            runtimeSnapshots: runtimeSnapshots,
            taskBoardSnapshot: taskBoardSnapshot,
            embeddedDisplaySnapshot: embeddedDisplaySnapshot
        )
        writeJSONLine(record, to: snapshotsFile)
    }

    public func recordContext(_ context: [String: String]) {
        let url = contextFile
        let encoder = self.encoder
        ioQueue.async {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                let data = try encoder.encode(context)
                try data.write(to: url, options: .atomic)
            } catch {
                // Ignore secondary context write failures.
            }
        }
    }

    public func recordDiagnostic(
        subsystem: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String] = [:],
        traceID: String = UUID().uuidString
    ) {
        let event = DiagnosticEvent(
            traceID: traceID,
            subsystem: subsystem,
            severity: severity,
            message: message,
            metadata: metadata
        )
        recentDiagnostics.insert(event, at: 0)
        if recentDiagnostics.count > maxRecentDiagnostics {
            recentDiagnostics = Array(recentDiagnostics.prefix(maxRecentDiagnostics))
        }
        writeJSONLine(event, to: diagnosticsFile)
    }

    public func captureReplayBundle(reason: String, provider: AgentProvider?) {
        let bundleID = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let replayDirectory = baseDirectory
            .appendingPathComponent("replay", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)

        let rawEvents = replayDirectory.appendingPathComponent("events.jsonl")
        let snapshots = replayDirectory.appendingPathComponent("snapshots.jsonl")
        let diagnostics = replayDirectory.appendingPathComponent("diagnostics.jsonl")
        let context = replayDirectory.appendingPathComponent("context.json")

        do {
            try fileManager.createDirectory(at: replayDirectory, withIntermediateDirectories: true, attributes: nil)
            if fileManager.fileExists(atPath: eventsFile.path) {
                try? fileManager.copyItem(at: eventsFile, to: rawEvents)
            }
            if fileManager.fileExists(atPath: snapshotsFile.path) {
                try? fileManager.copyItem(at: snapshotsFile, to: snapshots)
            }
            if fileManager.fileExists(atPath: diagnosticsFile.path) {
                try? fileManager.copyItem(at: diagnosticsFile, to: diagnostics)
            }
            if fileManager.fileExists(atPath: contextFile.path) {
                try? fileManager.copyItem(at: contextFile, to: context)
            }

            let bundle = ReplayBundle(
                bundleID: bundleID,
                provider: provider,
                rawEventsFile: rawEvents,
                snapshotsFile: snapshots,
                diagnosticsFile: diagnostics,
                appContextFile: context
            )
            recentBundles.insert(bundle, at: 0)
            if recentBundles.count > maxRecentBundles {
                recentBundles = Array(recentBundles.prefix(maxRecentBundles))
            }

            recordDiagnostic(
                subsystem: "replay",
                severity: .warning,
                message: "Captured replay bundle",
                metadata: [
                    "bundleID": bundleID,
                    "reason": reason,
                    "provider": provider?.displayName ?? "all"
                ]
            )
        } catch {
            recordDiagnostic(
                subsystem: "replay",
                severity: .error,
                message: "Failed to capture replay bundle",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func prepareDirectories() {
        [
            baseDirectory.appendingPathComponent("events", isDirectory: true),
            baseDirectory.appendingPathComponent("state", isDirectory: true),
            baseDirectory.appendingPathComponent("diagnostics", isDirectory: true),
            baseDirectory.appendingPathComponent("replay", isDirectory: true)
        ].forEach { directory in
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private func writeJSONLine<T: Encodable>(_ value: T, to url: URL) {
        let data: Data
        do {
            var encoded = try encoder.encode(value)
            encoded.append(0x0A)
            data = encoded
        } catch {
            return
        }

        ioQueue.async {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                if !fileManager.fileExists(atPath: url.path) {
                    fileManager.createFile(atPath: url.path, contents: data)
                    return
                }
                let handle = try FileHandle(forWritingTo: url)
                defer {
                    try? handle.close()
                }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Avoid recursive diagnostics if logging itself fails.
            }
        }
    }
}
