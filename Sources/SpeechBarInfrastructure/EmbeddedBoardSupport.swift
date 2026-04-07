import Foundation
import SpeechBarDomain

private enum EmbeddedBinaryValue {
    static func uint8(_ value: UInt8) -> Data {
        Data([value])
    }

    static func uint16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    static func uint64(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

public struct EmbeddedDisplayEncoder: EmbeddedDisplayEncoding {
    private let protocolVersion: UInt8

    public init(protocolVersion: UInt8 = 1) {
        self.protocolVersion = protocolVersion
    }

    public func makeFrames(
        for snapshot: EmbeddedDisplaySnapshot,
        mtu: Int?
    ) throws -> [EmbeddedBoardPacketFrame] {
        let payload = encodedPayload(for: snapshot)
        let maxPayload = max(32, mtu ?? 64)
        let chunkCapacity = max(1, maxPayload - 17)
        let chunkCount = max(1, Int(ceil(Double(payload.count) / Double(chunkCapacity))))

        return stride(from: 0, to: payload.count, by: chunkCapacity).enumerated().map { index, offset in
            let chunk = payload.subdata(in: offset..<min(offset + chunkCapacity, payload.count))
            var framePayload = Data()
            framePayload.append(EmbeddedBinaryValue.uint64(snapshot.sequence))
            framePayload.append(EmbeddedBinaryValue.uint16(UInt16(index)))
            framePayload.append(EmbeddedBinaryValue.uint16(UInt16(chunkCount)))
            framePayload.append(EmbeddedBinaryValue.uint32(UInt32(payload.count)))
            framePayload.append(EmbeddedBinaryValue.uint8(1))
            framePayload.append(chunk)
            return EmbeddedBoardPacketFrame(
                kind: .displaySnapshotFrame,
                sequence: snapshot.sequence,
                chunkIndex: index,
                chunkCount: chunkCount,
                payload: framePayload,
                createdAt: snapshot.generatedAt
            )
        }
    }

    public func digest(for snapshot: EmbeddedDisplaySnapshot) throws -> Data {
        encodedPayload(for: snapshot)
    }

    private func encodedPayload(for snapshot: EmbeddedDisplaySnapshot) -> Data {
        var body = Data()
        body.append(EmbeddedBinaryValue.uint8(protocolVersion))
        body.append(EmbeddedBinaryValue.uint8(modeCode(snapshot.mode)))
        body.append(EmbeddedBinaryValue.uint64(snapshot.sequence))
        body.append(EmbeddedBinaryValue.uint64(UInt64(snapshot.generatedAt.timeIntervalSince1970 * 1_000)))

        let cards = snapshot.taskBoard?.cards ?? []
        let selectedIndex = cards.firstIndex(where: \.isSelected).map(UInt8.init) ?? UInt8.max
        body.append(EmbeddedBinaryValue.uint8(UInt8(cards.count)))
        body.append(EmbeddedBinaryValue.uint8(UInt8(snapshot.taskBoard?.hiddenCount ?? 0)))
        body.append(EmbeddedBinaryValue.uint8(selectedIndex))
        body.append(EmbeddedBinaryValue.uint8(UInt8(snapshot.taskBoard?.providerSummaries.count ?? 0)))

        for card in cards.prefix(5) {
            body.append(EmbeddedBinaryValue.uint8(providerCode(card.provider)))
            body.append(EmbeddedBinaryValue.uint8(boardStateCode(card.boardState)))
            body.append(EmbeddedBinaryValue.uint8(card.isSelected ? 1 : 0))
            body.append(EmbeddedBinaryValue.uint8(0))
            body.append(EmbeddedBinaryValue.uint32(UInt32(max(0, card.elapsedSeconds))))
            body.append(fixedUTF8(card.title, byteCount: 32))
            body.append(fixedUTF8(card.progressText, byteCount: 64))
        }

        for summary in snapshot.taskBoard?.providerSummaries.prefix(4) ?? [] {
            body.append(EmbeddedBinaryValue.uint8(providerCode(summary.provider)))
            body.append(EmbeddedBinaryValue.uint8(UInt8(min(summary.activeTaskCount, 255))))
            body.append(EmbeddedBinaryValue.uint8(UInt8(min(summary.waitingInputCount, 255))))
            body.append(EmbeddedBinaryValue.uint8(UInt8(min(summary.waitingApprovalCount, 255))))
            body.append(EmbeddedBinaryValue.uint8(UInt8(min(summary.errorCount, 255))))
            body.append(EmbeddedBinaryValue.uint8(quotaCode(summary.quotaStatus.availability)))
        }

        let bars = snapshot.waveform?.levelBars ?? []
        body.append(EmbeddedBinaryValue.uint8(UInt8(min(bars.count, 32))))
        body.append(EmbeddedBinaryValue.uint8(snapshot.waveform?.peak ?? 0))
        for bar in bars.prefix(32) {
            body.append(EmbeddedBinaryValue.uint8(bar))
        }

        let crc = CRC32.checksum(body)
        body.append(EmbeddedBinaryValue.uint32(crc))
        return body
    }

    private func fixedUTF8(_ value: String, byteCount: Int) -> Data {
        let truncated = UTF8SafeTruncator.truncated(value, maxByteCount: byteCount)
        var data = Data(truncated.utf8)
        if data.count < byteCount {
            data.append(Data(repeating: 0, count: byteCount - data.count))
        }
        return data
    }

    private func modeCode(_ mode: EmbeddedDisplayMode) -> UInt8 {
        switch mode {
        case .multiTaskBoard:
            return 1
        case .audioWaveform:
            return 2
        case .blank:
            return 3
        case .booting:
            return 4
        case .error:
            return 5
        }
    }

    private func providerCode(_ provider: AgentProvider) -> UInt8 {
        switch provider {
        case .claudeCode:
            return 1
        case .codexCLI:
            return 2
        case .geminiCLI:
            return 3
        case .cursorAgent:
            return 4
        }
    }

    private func boardStateCode(_ state: BoardState) -> UInt8 {
        switch state {
        case .run:
            return 1
        case .check:
            return 2
        case .input:
            return 3
        case .approve:
            return 4
        case .error:
            return 5
        }
    }

    private func quotaCode(_ availability: QuotaAvailability) -> UInt8 {
        switch availability {
        case .available:
            return 1
        case .unknown:
            return 2
        case .error:
            return 3
        }
    }
}

public final class LoopbackBoardTransport: EmbeddedBoardTransport, @unchecked Sendable {
    public let inboundEvents: AsyncStream<EmbeddedBoardInboundEvent>
    public let connectionStates: AsyncStream<EmbeddedBoardConnectionState>
    public let supportsFragmentation: Bool = true
    public let supportsBidirectionalEvents: Bool = true

    private let inboundContinuation: AsyncStream<EmbeddedBoardInboundEvent>.Continuation
    private let connectionContinuation: AsyncStream<EmbeddedBoardConnectionState>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.transport.loopback")
    private var isRunning = false
    private(set) var sentFrames: [EmbeddedBoardPacketFrame] = []

    public init() {
        var capturedInbound: AsyncStream<EmbeddedBoardInboundEvent>.Continuation?
        var capturedConnection: AsyncStream<EmbeddedBoardConnectionState>.Continuation?
        self.inboundEvents = AsyncStream { continuation in
            capturedInbound = continuation
        }
        self.connectionStates = AsyncStream { continuation in
            capturedConnection = continuation
        }
        self.inboundContinuation = capturedInbound!
        self.connectionContinuation = capturedConnection!
    }

    public func start() async {
        stateQueue.sync {
            guard !isRunning else { return }
            isRunning = true
        }
        let info = EmbeddedBoardDeviceInfo(
            deviceID: "loopback",
            firmwareVersion: "debug",
            protocolVersion: 1,
            screenWidth: 284,
            screenHeight: 76,
            maxPayloadBytes: 256,
            transportKind: .loopback,
            supportsInputReturn: true
        )
        connectionContinuation.yield(EmbeddedBoardConnectionState(phase: .ready, deviceInfo: info))
        inboundContinuation.yield(.helloAck(info))
    }

    public func stop() async {
        stateQueue.sync {
            isRunning = false
        }
        connectionContinuation.yield(.disconnected)
    }

    public func send(_ frame: EmbeddedBoardPacketFrame) async throws {
        stateQueue.sync {
            sentFrames.append(frame)
        }
        inboundContinuation.yield(.ack(sequence: frame.sequence))
    }
}

public final class FileDumpBoardTransport: EmbeddedBoardTransport, @unchecked Sendable {
    public let inboundEvents: AsyncStream<EmbeddedBoardInboundEvent>
    public let connectionStates: AsyncStream<EmbeddedBoardConnectionState>
    public let supportsFragmentation: Bool = true
    public let supportsBidirectionalEvents: Bool = true

    private let inboundContinuation: AsyncStream<EmbeddedBoardInboundEvent>.Continuation
    private let connectionContinuation: AsyncStream<EmbeddedBoardConnectionState>.Continuation
    private let dumpDirectory: URL
    private let fileManager: FileManager

    public init(
        dumpDirectory: URL = AgentMonitorPaths.stateDirectory().appendingPathComponent("embedded-frames", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.dumpDirectory = dumpDirectory
        self.fileManager = fileManager
        var capturedInbound: AsyncStream<EmbeddedBoardInboundEvent>.Continuation?
        var capturedConnection: AsyncStream<EmbeddedBoardConnectionState>.Continuation?
        self.inboundEvents = AsyncStream { continuation in
            capturedInbound = continuation
        }
        self.connectionStates = AsyncStream { continuation in
            capturedConnection = continuation
        }
        self.inboundContinuation = capturedInbound!
        self.connectionContinuation = capturedConnection!
    }

    public func start() async {
        try? fileManager.createDirectory(at: dumpDirectory, withIntermediateDirectories: true, attributes: nil)
        let info = EmbeddedBoardDeviceInfo(
            deviceID: "file-dump",
            firmwareVersion: "debug",
            protocolVersion: 1,
            screenWidth: 284,
            screenHeight: 76,
            maxPayloadBytes: 512,
            transportKind: .fileDump,
            supportsInputReturn: true
        )
        connectionContinuation.yield(EmbeddedBoardConnectionState(phase: .ready, deviceInfo: info))
        inboundContinuation.yield(.helloAck(info))
    }

    public func stop() async {
        connectionContinuation.yield(.disconnected)
    }

    public func send(_ frame: EmbeddedBoardPacketFrame) async throws {
        try fileManager.createDirectory(at: dumpDirectory, withIntermediateDirectories: true, attributes: nil)
        let filename = String(format: "%020llu-%02d-of-%02d.bin", frame.sequence, frame.chunkIndex, frame.chunkCount)
        let url = dumpDirectory.appendingPathComponent(filename)
        try frame.payload.write(to: url, options: .atomic)
        inboundContinuation.yield(.ack(sequence: frame.sequence))
    }
}

public final class HIDBoardTransport: EmbeddedBoardTransport, @unchecked Sendable {
    public let inboundEvents: AsyncStream<EmbeddedBoardInboundEvent>
    public let connectionStates: AsyncStream<EmbeddedBoardConnectionState>
    public let supportsFragmentation: Bool = true
    public let supportsBidirectionalEvents: Bool = true

    private let inboundContinuation: AsyncStream<EmbeddedBoardInboundEvent>.Continuation
    private let connectionContinuation: AsyncStream<EmbeddedBoardConnectionState>.Continuation

    public init() {
        var capturedInbound: AsyncStream<EmbeddedBoardInboundEvent>.Continuation?
        var capturedConnection: AsyncStream<EmbeddedBoardConnectionState>.Continuation?
        self.inboundEvents = AsyncStream { continuation in
            capturedInbound = continuation
        }
        self.connectionStates = AsyncStream { continuation in
            capturedConnection = continuation
        }
        self.inboundContinuation = capturedInbound!
        self.connectionContinuation = capturedConnection!
    }

    public func start() async {
        connectionContinuation.yield(
            EmbeddedBoardConnectionState(
                phase: .degraded,
                reason: "HID transport is reserved for future hardware integration."
            )
        )
    }

    public func stop() async {
        connectionContinuation.yield(.disconnected)
    }

    public func send(_ frame: EmbeddedBoardPacketFrame) async throws {
        throw NSError(
            domain: "HIDBoardTransport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "HID transport is not implemented yet."]
        )
    }
}

public final class CDCBoardTransport: EmbeddedBoardTransport, @unchecked Sendable {
    public let inboundEvents: AsyncStream<EmbeddedBoardInboundEvent>
    public let connectionStates: AsyncStream<EmbeddedBoardConnectionState>
    public let supportsFragmentation: Bool = true
    public let supportsBidirectionalEvents: Bool = true

    private let inboundContinuation: AsyncStream<EmbeddedBoardInboundEvent>.Continuation
    private let connectionContinuation: AsyncStream<EmbeddedBoardConnectionState>.Continuation

    public init() {
        var capturedInbound: AsyncStream<EmbeddedBoardInboundEvent>.Continuation?
        var capturedConnection: AsyncStream<EmbeddedBoardConnectionState>.Continuation?
        self.inboundEvents = AsyncStream { continuation in
            capturedInbound = continuation
        }
        self.connectionStates = AsyncStream { continuation in
            capturedConnection = continuation
        }
        self.inboundContinuation = capturedInbound!
        self.connectionContinuation = capturedConnection!
    }

    public func start() async {
        connectionContinuation.yield(
            EmbeddedBoardConnectionState(
                phase: .degraded,
                reason: "CDC transport is reserved for future hardware integration."
            )
        )
    }

    public func stop() async {
        connectionContinuation.yield(.disconnected)
    }

    public func send(_ frame: EmbeddedBoardPacketFrame) async throws {
        throw NSError(
            domain: "CDCBoardTransport",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "CDC transport is not implemented yet."]
        )
    }
}
