import Foundation
import SpeechBarDomain

private func boardInputDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [BoardInput] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

private struct BoardInputEventRecord: Decodable {
    let kind: String
    let source: String?
    let occurredAt: String?
}

public final class BoardEventFileHardwareEventSource: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let fileURL: URL
    private let fileManager: FileManager
    private let pollingInterval: Duration
    private let startAtEnd: Bool
    private let stateLock = NSLock()
    private let timestampParser = ISO8601DateFormatter()

    private var pollingTask: Task<Void, Never>?
    private var fileOffset: UInt64 = 0
    private var partialLineBuffer = Data()
    private var hasPrimedInitialOffset = false

    public init(
        fileURL: URL = BoardInputPaths.eventsFileURL(),
        fileManager: FileManager = .default,
        pollingInterval: Duration = .milliseconds(180),
        startAtEnd: Bool = true,
        startImmediately: Bool = true
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.pollingInterval = pollingInterval
        self.startAtEnd = startAtEnd

        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        if startImmediately {
            start()
        }
    }

    deinit {
        stop()
        continuation.finish()
    }

    public func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            await self?.runPollingLoop()
        }
    }

    public func stop() {
        stateLock.lock()
        let task = pollingTask
        pollingTask = nil
        stateLock.unlock()
        task?.cancel()
    }

    private func runPollingLoop() async {
        boardInputDebugLog("watching board input file: \(fileURL.path)")

        while !Task.isCancelled {
            do {
                try pollOnce()
            } catch {
                boardInputDebugLog("poll failed: \(error.localizedDescription)")
            }

            do {
                try await Task.sleep(for: pollingInterval)
            } catch {
                return
            }
        }
    }

    private func pollOnce() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        if !hasPrimedInitialOffset {
            hasPrimedInitialOffset = true
            if startAtEnd {
                fileOffset = fileSize
                boardInputDebugLog("primed board input offset at EOF=\(fileOffset)")
                return
            }
        }

        if fileSize < fileOffset {
            boardInputDebugLog("board input file truncated, rewinding to start")
            fileOffset = 0
            partialLineBuffer = Data()
        }

        guard fileSize > fileOffset else {
            return
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffset += UInt64(data.count)
        partialLineBuffer.append(data)
        processBufferedLines()
    }

    private func processBufferedLines() {
        while let newlineIndex = partialLineBuffer.firstIndex(of: 0x0A) {
            let lineData = partialLineBuffer.prefix(upTo: newlineIndex)
            partialLineBuffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else { continue }
            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else {
                continue
            }

            guard let event = decodeHardwareEvent(from: line) else {
                boardInputDebugLog("ignored malformed board input line")
                continue
            }

            boardInputDebugLog("event kind=\(event.kind.rawValue) source=\(event.source.rawValue)")
            continuation.yield(event)
        }
    }

    private func decodeHardwareEvent(from line: String) -> HardwareEvent? {
        guard let data = line.data(using: .utf8),
              let record = try? JSONDecoder().decode(BoardInputEventRecord.self, from: data),
              let kind = hardwareEventKind(for: record.kind)
        else {
            return nil
        }

        let source = hardwareSourceKind(for: record.source)
        let occurredAt = record.occurredAt.flatMap(timestampParser.date(from:)) ?? Date()

        return HardwareEvent(
            source: source,
            kind: kind,
            occurredAt: occurredAt
        )
    }

    private func hardwareEventKind(for rawValue: String) -> HardwareEventKind? {
        switch rawValue {
        case "pushToTalkPressed":
            return .pushToTalkPressed
        case "pushToTalkReleased":
            return .pushToTalkReleased
        case "rotaryClockwise":
            return .rotaryClockwise
        case "rotaryCounterClockwise":
            return .rotaryCounterClockwise
        case "pressPrimary":
            return .pressPrimary
        case "pressSecondary":
            return .pressSecondary
        case "dismissSelected":
            return .dismissSelected
        case "switchBoardNext":
            return .switchBoardNext
        case "switchBoardPrevious":
            return .switchBoardPrevious
        default:
            return nil
        }
    }

    private func hardwareSourceKind(for rawValue: String?) -> HardwareSourceKind {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "usbRotaryKnob":
            return .usbRotaryKnob
        case "usbHID", "usb", "cdc", "board":
            return .usbHID
        default:
            return .usbHID
        }
    }
}
