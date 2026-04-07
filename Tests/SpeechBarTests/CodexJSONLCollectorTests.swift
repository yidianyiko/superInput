import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarInfrastructure

@Suite("CodexJSONLCollector")
struct CodexJSONLCollectorTests {
    @Test
    func incrementalReaderHandlesPartialJSONLLines() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let fileURL = try makeCodexRolloutFile(baseDirectory: root, date: now)
        let initialLog =
            #"{"type":"session_meta","payload":{"cwd":"/tmp/project"}}"# + "\n" +
            #"{"type":"event_msg","payload":{"type":"task_started","title":"Build project""#
        try initialLog.write(to: fileURL, atomically: true, encoding: .utf8)

        let collector = CodexJSONLCollector(
            baseDirectory: root,
            pollInterval: .seconds(60),
            activeFileThreshold: 3_600,
            staleSessionThreshold: 600,
            approvalHeuristicThreshold: 0.1
        )
        let firstPass = await collector.pollOnce(now: now)
        #expect(firstPass.map(\.kind) == [.sessionStarted])

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        let appendedLog = "}}\n" + #"{"type":"event_msg","payload":{"type":"task_complete"}}"# + "\n"
        try handle.write(contentsOf: Data(appendedLog.utf8))
        try handle.close()

        let secondPass = await collector.pollOnce(now: now.addingTimeInterval(1))
        let events = firstPass + secondPass
        #expect(events.map(\.kind) == [.sessionStarted, .taskStarted, .taskFinished])
    }

    @Test
    func shellCommandWithoutCompletionBecomesWaitingApproval() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 1_710_100_000)
        let fileURL = try makeCodexRolloutFile(baseDirectory: root, date: now)
        let log =
            #"{"type":"session_meta","payload":{"cwd":"/tmp/project"}}"# + "\n" +
            #"{"type":"response_item","payload":{"type":"function_call","name":"shell_command","arguments":"{\"command\":\"ls -la\"}"}}"# + "\n"
        try log.write(to: fileURL, atomically: true, encoding: .utf8)

        let collector = CodexJSONLCollector(
            baseDirectory: root,
            pollInterval: .seconds(60),
            activeFileThreshold: 3_600,
            staleSessionThreshold: 600,
            approvalHeuristicThreshold: 0.1
        )
        let firstPass = await collector.pollOnce(now: now)
        let secondPass = await collector.pollOnce(now: now.addingTimeInterval(1))
        let approval = (firstPass + secondPass).first { $0.kind == .waitingApproval }
        #expect(approval != nil)
    }
}

private func makeCodexRolloutFile(baseDirectory: URL, date: Date) throws -> URL {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    let directory = baseDirectory
        .appendingPathComponent(String(format: "%04d", components.year ?? 2026), isDirectory: true)
        .appendingPathComponent(String(format: "%02d", components.month ?? 1), isDirectory: true)
        .appendingPathComponent(String(format: "%02d", components.day ?? 1), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    return directory.appendingPathComponent("rollout-2026-04-05T10-10-10-00000000-0000-0000-0000-000000000000.jsonl")
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}
