import Combine
import Foundation
import SpeechBarDomain

@MainActor
public final class EmbeddedDisplayCoordinator: ObservableObject {
    private static let defaultSnapshotRebuildDebounceDuration: Duration = .milliseconds(120)

    @Published public private(set) var connectionState: EmbeddedBoardConnectionState = .disconnected
    @Published public private(set) var lastSnapshot: EmbeddedDisplaySnapshot?
    @Published public private(set) var lastSentAt: Date?
    @Published public private(set) var lastAckedSequence: UInt64?
    @Published public private(set) var lastEncodedByteCount = 0
    @Published public private(set) var lastFrameCount = 0
    @Published public private(set) var lastNackCode: String?
    @Published public private(set) var lastDeviceStatus: DeviceStatusSnapshot?

    private let voiceCoordinator: VoiceSessionCoordinator
    private let monitorCoordinator: AgentMonitorCoordinator
    private let diagnostics: DiagnosticsCoordinator
    private let displayBuilder: any EmbeddedDisplaySnapshotBuilding
    private let encoder: any EmbeddedDisplayEncoding
    private let transport: any EmbeddedBoardTransport
    private let sleepClock: any SleepClock
    private let snapshotRebuildDebounceDuration: Duration

    private var cancellables: Set<AnyCancellable> = []
    private var inboundTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var pendingRebuildTask: Task<Void, Never>?
    private var pendingSendTask: Task<Void, Never>?
    private var pendingAckTasks: [UInt64: Task<Void, Never>] = [:]
    private var hasStarted = false
    private var sequence: UInt64 = 0
    private var lastSentDigest = Data()
    private var lastRebuiltAt = Date.distantPast
    private var currentHeartbeatInterval: Duration = .seconds(1)
    private var consecutiveTransportFailures = 0

    public init(
        voiceCoordinator: VoiceSessionCoordinator,
        monitorCoordinator: AgentMonitorCoordinator,
        diagnostics: DiagnosticsCoordinator,
        displayBuilder: any EmbeddedDisplaySnapshotBuilding,
        encoder: any EmbeddedDisplayEncoding,
        transport: any EmbeddedBoardTransport,
        sleepClock: any SleepClock = ContinuousSleepClock(),
        snapshotRebuildDebounceDuration: Duration = .milliseconds(120)
    ) {
        self.voiceCoordinator = voiceCoordinator
        self.monitorCoordinator = monitorCoordinator
        self.diagnostics = diagnostics
        self.displayBuilder = displayBuilder
        self.encoder = encoder
        self.transport = transport
        self.sleepClock = sleepClock
        self.snapshotRebuildDebounceDuration = snapshotRebuildDebounceDuration
    }

    deinit {
        inboundTask?.cancel()
        connectionTask?.cancel()
        heartbeatTask?.cancel()
        pendingRebuildTask?.cancel()
        pendingSendTask?.cancel()
        pendingAckTasks.values.forEach { $0.cancel() }
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        bindInputs()

        connectionTask = Task { [weak self] in
            guard let self else { return }
            await transport.start()
            for await state in transport.connectionStates {
                self.handleConnectionState(state)
            }
        }

        inboundTask = Task { [weak self] in
            guard let self else { return }
            for await event in transport.inboundEvents {
                self.handleInboundEvent(event)
            }
        }

        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: currentHeartbeatInterval)
                await self.sendCurrentSnapshot(force: true, reason: "heartbeat")
            }
        }

        rebuildSnapshot(reason: "startup", forceSend: true)
    }

    private func bindInputs() {
        monitorCoordinator.$taskBoardSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRebuild(reason: "task-board-update", forceSend: false)
            }
            .store(in: &cancellables)

        voiceCoordinator.$audioLevelWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRebuild(reason: "audio-level", forceSend: false)
            }
            .store(in: &cancellables)

        voiceCoordinator.$overlayPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.pendingRebuildTask?.cancel()
                self?.rebuildSnapshot(reason: "overlay-phase", forceSend: true)
            }
            .store(in: &cancellables)

        voiceCoordinator.$overlaySubtitle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRebuild(reason: "overlay-subtitle", forceSend: false)
            }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRebuild(reason: String, forceSend: Bool) {
        pendingRebuildTask?.cancel()
        let debounceDuration = snapshotRebuildDebounceDuration
        pendingRebuildTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleepClock.sleep(for: debounceDuration)
            } catch {
                return
            }
            self.performScheduledSnapshotRebuild(reason: reason, forceSend: forceSend)
        }
    }

    private func performScheduledSnapshotRebuild(reason: String, forceSend: Bool) {
        pendingRebuildTask = nil
        rebuildSnapshot(reason: reason, forceSend: forceSend)
    }

    private func rebuildSnapshot(reason: String, forceSend: Bool) {
        sequence += 1
        let mode = inferredDisplayMode()
        let waveform = inferredWaveformSnapshot()
        let snapshot = displayBuilder.makeSnapshot(
            sequence: sequence,
            mode: mode,
            taskBoard: monitorCoordinator.taskBoardSnapshot,
            waveform: waveform,
            generatedAt: Date()
        )
        lastSnapshot = snapshot
        lastRebuiltAt = snapshot.generatedAt
        diagnostics.recordSnapshots(
            runtimeSnapshots: monitorCoordinator.runtimeSnapshots,
            taskBoardSnapshot: monitorCoordinator.taskBoardSnapshot,
            embeddedDisplaySnapshot: snapshot
        )

        pendingSendTask?.cancel()
        pendingSendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.sendCurrentSnapshot(force: forceSend, reason: reason)
        }
    }

    private func sendCurrentSnapshot(force: Bool, reason: String) async {
        guard let snapshot = lastSnapshot else { return }
        do {
            let digest = try encoder.digest(for: snapshot)
            if !force && digest == lastSentDigest {
                return
            }

            let encodeStartedAt = Date()
            let frames = try encoder.makeFrames(for: snapshot, mtu: connectionState.deviceInfo?.maxPayloadBytes)
            let byteCount = frames.reduce(0) { $0 + $1.payload.count }
            lastEncodedByteCount = byteCount
            lastFrameCount = frames.count

            for frame in frames {
                try await transport.send(frame)
            }

            lastSentDigest = digest
            lastSentAt = Date()
            consecutiveTransportFailures = 0
            scheduleAckTimeout(for: snapshot.sequence)

            diagnostics.recordDiagnostic(
                subsystem: "embedded-display.send",
                severity: .info,
                message: "Sent display snapshot",
                metadata: [
                    "reason": reason,
                    "sequence": String(snapshot.sequence),
                    "frameCount": String(frames.count),
                    "byteCount": String(byteCount),
                    "durationMs": String(Int(Date().timeIntervalSince(encodeStartedAt) * 1_000))
                ]
            )
        } catch {
            consecutiveTransportFailures += 1
            diagnostics.recordDiagnostic(
                subsystem: "embedded-display.send",
                severity: .error,
                message: "Failed to send display snapshot",
                metadata: [
                    "reason": reason,
                    "error": error.localizedDescription,
                    "failureCount": String(consecutiveTransportFailures)
                ]
            )
            diagnostics.captureReplayBundle(reason: "transport-send-failure", provider: nil)
        }
    }

    private func handleConnectionState(_ state: EmbeddedBoardConnectionState) {
        connectionState = state
        diagnostics.recordDiagnostic(
            subsystem: "embedded-display.connection",
            severity: state.phase == .failed ? .error : .info,
            message: "Transport connection state changed",
            metadata: [
                "phase": state.phase.rawValue,
                "reason": state.reason ?? "",
                "transport": state.deviceInfo?.transportKind.rawValue ?? "unknown"
            ]
        )
    }

    private func handleInboundEvent(_ event: EmbeddedBoardInboundEvent) {
        switch event {
        case .helloAck(let deviceInfo):
            connectionState = EmbeddedBoardConnectionState(phase: .ready, deviceInfo: deviceInfo)
        case .ack(let sequence):
            lastAckedSequence = sequence
            pendingAckTasks.removeValue(forKey: sequence)?.cancel()
        case .nack(let sequence, let code):
            lastNackCode = code
            pendingAckTasks.removeValue(forKey: sequence)?.cancel()
            diagnostics.recordDiagnostic(
                subsystem: "embedded-display.transport",
                severity: .warning,
                message: "Device returned NACK",
                metadata: [
                    "sequence": String(sequence),
                    "code": code
                ]
            )
            consecutiveTransportFailures += 1
            if consecutiveTransportFailures >= 3 {
                currentHeartbeatInterval = .seconds(2)
            }
        case .deviceStatus(let snapshot):
            lastDeviceStatus = snapshot
        case .input(let input):
            handleInputEvent(input)
        case .pong:
            break
        }
    }

    private func handleInputEvent(_ input: EmbeddedBoardInputEventKind) {
        switch input {
        case .rotateNext:
            monitorCoordinator.moveToNextCard()
        case .rotatePrevious:
            monitorCoordinator.moveToPreviousCard()
        case .pressPrimary:
            monitorCoordinator.setGlobalBrowseMode(true)
        case .pressSecondary:
            monitorCoordinator.setGlobalBrowseMode(false)
        case .dismissSelected:
            monitorCoordinator.dismissSelectedCard()
        }
    }

    private func scheduleAckTimeout(for sequence: UInt64) {
        pendingAckTasks[sequence]?.cancel()
        pendingAckTasks[sequence] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            self?.handleAckTimeout(sequence: sequence)
        }
    }

    private func handleAckTimeout(sequence: UInt64) {
        guard lastAckedSequence != sequence else { return }
        diagnostics.recordDiagnostic(
            subsystem: "embedded-display.transport",
            severity: .warning,
            message: "ACK timeout",
            metadata: ["sequence": String(sequence)]
        )
        consecutiveTransportFailures += 1
        if consecutiveTransportFailures >= 3 {
            currentHeartbeatInterval = .seconds(2)
        }
    }

    private func inferredDisplayMode() -> EmbeddedDisplayMode {
        switch voiceCoordinator.overlayPhase {
        case .recording, .finalizing, .polishing, .publishing:
            return .audioWaveform
        case .failed:
            return .error
        case .hidden:
            return monitorCoordinator.taskBoardSnapshot.cards.isEmpty ? .blank : .multiTaskBoard
        }
    }

    private func inferredWaveformSnapshot() -> AudioWaveformSnapshot {
        let samples = voiceCoordinator.audioLevelWindow
        let bars = samples.suffix(24).map { sample in
            UInt8(max(0, min(100, Int(sample.level * 100))))
        }
        let peak = UInt8(max(0, min(100, Int((samples.map(\.peak).max() ?? 0) * 100))))
        return AudioWaveformSnapshot(
            levelBars: bars,
            peak: peak,
            recordingState: String(describing: voiceCoordinator.overlayPhase),
            subtitle: voiceCoordinator.overlaySubtitle,
            capturedAt: Date()
        )
    }
}
