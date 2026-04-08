import Foundation
import Testing
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("BoardEventFileHardwareEventSource")
struct BoardEventFileHardwareEventSourceTests {
    @Test
    func appendedJSONLBoardEventBecomesHardwareEvent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoardEventFileHardwareEventSourceTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("events.jsonl")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let source = BoardEventFileHardwareEventSource(
            fileURL: fileURL,
            pollingInterval: .milliseconds(20),
            startAtEnd: false
        )
        defer { source.stop() }

        let eventTask = Task {
            var iterator = source.events.makeAsyncIterator()
            return await iterator.next()
        }

        let line = """
        {"kind":"pushToTalkPressed","source":"usbHID","occurredAt":"2026-04-08T12:00:00Z"}
        """
        try (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let event = await eventTask.value
        #expect(event?.kind == .pushToTalkPressed)
        #expect(event?.source == .usbHID)
    }
}
