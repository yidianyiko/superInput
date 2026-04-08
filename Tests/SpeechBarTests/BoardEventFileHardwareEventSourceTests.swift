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
<<<<<<< HEAD

    @Test
    func boardSpecificEventKindsAreDecodedFromJSONL() async throws {
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
            var events: [HardwareEvent] = []
            while events.count < 5, let next = await iterator.next() {
                events.append(next)
            }
            return events
        }

        let lines = [
            #"{"kind":"pressPrimary","source":"board"}"#,
            #"{"kind":"pressSecondary","source":"board"}"#,
            #"{"kind":"dismissSelected","source":"board"}"#,
            #"{"kind":"switchBoardNext","source":"board"}"#,
            #"{"kind":"switchBoardPrevious","source":"board"}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let events = await eventTask.value
        #expect(events.map(\.kind) == [
            .pressPrimary,
            .pressSecondary,
            .dismissSelected,
            .switchBoardNext,
            .switchBoardPrevious
        ])
        #expect(events.allSatisfy { $0.source == .usbHID })
    }
=======
>>>>>>> 5fe97d2 (Day 0408 & First Word detect)
}
