import Foundation
import SpeechBarDomain

protocol RecordingHotkeyRuntimeSource: HardwareEventSource {
    var requiresAccessibility: Bool { get }
    var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot { get }
    var diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot> { get }
    func shutdown()
}

public final class RecordingHotkeyController: HardwareEventSource, @unchecked Sendable {
    public let events: AsyncStream<HardwareEvent>
    public let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>

    public var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot {
        stateQueue.sync { diagnosticsSnapshotStorage }
    }

    private let continuation: AsyncStream<HardwareEvent>.Continuation
    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation
    private let stateQueue = DispatchQueue(label: "com.startup.speechbar.recording-hotkey-controller")
    private let rightCommandSourceFactory: @Sendable () -> any RecordingHotkeyRuntimeSource
    private let customComboSourceFactory: @Sendable (RecordingHotkeyConfiguration) -> any RecordingHotkeyRuntimeSource

    private var diagnosticsSnapshotStorage: RecordingHotkeyDiagnosticsSnapshot
    private var lastTrigger: RecordingHotkeyLastTrigger?
    private var activeSource: (any RecordingHotkeyRuntimeSource)?
    private var activeEventsTask: Task<Void, Never>?
    private var activeDiagnosticsTask: Task<Void, Never>?
    private var activeGeneration: UInt64 = 0

    public convenience init(configuration: RecordingHotkeyConfiguration = .defaultRightCommand) {
        self.init(
            configuration: configuration,
            rightCommandSourceFactory: { GlobalRightCommandPushToTalkSource() },
            customComboSourceFactory: { GlobalShortcutRecordingHotkeySource(configuration: $0) }
        )
    }

    init(
        configuration: RecordingHotkeyConfiguration,
        rightCommandSourceFactory: @escaping @Sendable () -> any RecordingHotkeyRuntimeSource,
        customComboSourceFactory: @escaping @Sendable (RecordingHotkeyConfiguration) -> any RecordingHotkeyRuntimeSource
    ) {
        var capturedContinuation: AsyncStream<HardwareEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        var capturedDiagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation?
        self.diagnosticsUpdates = AsyncStream { continuation in
            capturedDiagnosticsContinuation = continuation
        }
        self.diagnosticsContinuation = capturedDiagnosticsContinuation!
        self.rightCommandSourceFactory = rightCommandSourceFactory
        self.customComboSourceFactory = customComboSourceFactory
        self.diagnosticsSnapshotStorage = RecordingHotkeyDiagnosticsSnapshot(
            configuration: configuration,
            registrationStatus: .invalidConfiguration,
            requiresAccessibility: false,
            accessibilityTrusted: true,
            lastTrigger: nil,
            guidanceText: nil
        )

        replaceActiveSource(with: configuration)
    }

    deinit {
        let sourceToShutdown: (any RecordingHotkeyRuntimeSource)? = stateQueue.sync {
            activeEventsTask?.cancel()
            activeDiagnosticsTask?.cancel()
            activeEventsTask = nil
            activeDiagnosticsTask = nil
            let source = activeSource
            activeSource = nil
            return source
        }
        sourceToShutdown?.shutdown()
        continuation.finish()
        diagnosticsContinuation.finish()
    }

    public func apply(_ configuration: RecordingHotkeyConfiguration) {
        replaceActiveSource(with: configuration)
    }

    private func replaceActiveSource(with configuration: RecordingHotkeyConfiguration) {
        let (generation, sourceToShutdown): (UInt64, (any RecordingHotkeyRuntimeSource)?) = stateQueue.sync {
            activeGeneration &+= 1
            activeEventsTask?.cancel()
            activeDiagnosticsTask?.cancel()
            activeEventsTask = nil
            activeDiagnosticsTask = nil
            let source = activeSource
            activeSource = nil
            return (activeGeneration, source)
        }
        sourceToShutdown?.shutdown()

        let source = makeSource(for: configuration)
        let sourceEvents = source.events
        let sourceDiagnosticsUpdates = source.diagnosticsUpdates
        let eventsTask = Task { [weak self] in
            for await event in sourceEvents {
                self?.relay(event, mode: configuration.mode, generation: generation)
            }
        }

        let diagnosticsTask = Task { [weak self] in
            for await snapshot in sourceDiagnosticsUpdates {
                self?.updateDiagnostics(snapshot, generation: generation)
            }
        }

        let installedSnapshot = stateQueue.sync { () -> RecordingHotkeyDiagnosticsSnapshot? in
            guard activeGeneration == generation else {
                return nil
            }
            activeSource = source
            let snapshot = mergedSnapshot(
                source.diagnosticsSnapshot,
                requiresAccessibility: source.requiresAccessibility,
                lastTrigger: lastTrigger
            )
            diagnosticsSnapshotStorage = snapshot
            activeEventsTask = eventsTask
            activeDiagnosticsTask = diagnosticsTask
            return snapshot
        }
        guard let installedSnapshot else {
            eventsTask.cancel()
            diagnosticsTask.cancel()
            source.shutdown()
            return
        }

        diagnosticsContinuation.yield(installedSnapshot)
    }

    private func makeSource(for configuration: RecordingHotkeyConfiguration) -> any RecordingHotkeyRuntimeSource {
        switch configuration.mode {
        case .rightCommand:
            rightCommandSourceFactory()
        case .customCombo:
            customComboSourceFactory(configuration)
        }
    }

    private func relay(_ event: HardwareEvent, mode: RecordingHotkeyMode, generation: UInt64) {
        var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot?
        var shouldYield = false

        stateQueue.sync {
            guard activeGeneration == generation else { return }

            if let lastTrigger = Self.lastTrigger(from: event, mode: mode) {
                self.lastTrigger = lastTrigger
                let snapshot = mergedSnapshot(
                    diagnosticsSnapshotStorage,
                    lastTrigger: lastTrigger
                )
                diagnosticsSnapshotStorage = snapshot
                diagnosticsSnapshot = snapshot
            }

            shouldYield = true
        }

        guard shouldYield else { return }
        continuation.yield(event)
        if let diagnosticsSnapshot {
            diagnosticsContinuation.yield(diagnosticsSnapshot)
        }
    }

    private func updateDiagnostics(_ snapshot: RecordingHotkeyDiagnosticsSnapshot, generation: UInt64) {
        let diagnosticsSnapshot = stateQueue.sync { () -> RecordingHotkeyDiagnosticsSnapshot? in
            guard activeGeneration == generation else { return nil }
            let nextSnapshot = mergedSnapshot(snapshot, lastTrigger: lastTrigger)
            guard nextSnapshot != diagnosticsSnapshotStorage else {
                return nil
            }
            diagnosticsSnapshotStorage = nextSnapshot
            return nextSnapshot
        }
        guard let diagnosticsSnapshot else { return }
        diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    private func mergedSnapshot(
        _ snapshot: RecordingHotkeyDiagnosticsSnapshot,
        requiresAccessibility: Bool? = nil,
        lastTrigger: RecordingHotkeyLastTrigger?
    ) -> RecordingHotkeyDiagnosticsSnapshot {
        RecordingHotkeyDiagnosticsSnapshot(
            configuration: snapshot.configuration,
            registrationStatus: snapshot.registrationStatus,
            requiresAccessibility: requiresAccessibility ?? snapshot.requiresAccessibility,
            accessibilityTrusted: snapshot.accessibilityTrusted,
            lastTrigger: lastTrigger,
            guidanceText: snapshot.guidanceText
        )
    }

    private static func lastTrigger(
        from event: HardwareEvent,
        mode: RecordingHotkeyMode
    ) -> RecordingHotkeyLastTrigger? {
        let action: RecordingHotkeyTriggerAction

        switch event.kind {
        case .pushToTalkPressed:
            action = .start
        case .pushToTalkReleased:
            action = .stop
        default:
            return nil
        }

        return RecordingHotkeyLastTrigger(
            occurredAt: event.occurredAt,
            mode: mode,
            action: action
        )
    }
}

private final class GlobalShortcutRecordingHotkeySource: RecordingHotkeyRuntimeSource, @unchecked Sendable {
    let events: AsyncStream<HardwareEvent>
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>
    let diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot
    let requiresAccessibility = false

    private var source: GlobalShortcutToggleSource?

    init(
        configuration: RecordingHotkeyConfiguration,
        registrar: GlobalHotKeyRegistering = SystemGlobalHotKeyRegistrar()
    ) {
        let source = GlobalShortcutToggleSource(
            combination: configuration.customCombination,
            registrar: registrar
        )
        let snapshot = Self.makeDiagnosticsSnapshot(
            configuration: configuration,
            registrationStatus: source.registrationStatusForTesting()
        )

        self.source = source
        self.events = source.events
        self.diagnosticsSnapshot = snapshot
        self.diagnosticsUpdates = AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func shutdown() {
        source = nil
    }

    private static func makeDiagnosticsSnapshot(
        configuration: RecordingHotkeyConfiguration,
        registrationStatus: RecordingHotkeyRegistrationStatus
    ) -> RecordingHotkeyDiagnosticsSnapshot {
        RecordingHotkeyDiagnosticsSnapshot(
            configuration: configuration,
            registrationStatus: registrationStatus,
            requiresAccessibility: false,
            accessibilityTrusted: true,
            lastTrigger: nil,
            guidanceText: guidanceText(
                for: registrationStatus,
                validationResult: configuration.customCombination.validationResult
            )
        )
    }

    private static func guidanceText(
        for registrationStatus: RecordingHotkeyRegistrationStatus,
        validationResult: RecordingHotkeyValidationResult
    ) -> String? {
        switch registrationStatus {
        case .registered:
            return nil
        case .permissionRequired:
            return "Accessibility access is not required for custom hotkeys."
        case .invalidConfiguration:
            switch validationResult {
            case .missingModifier:
                return "Add at least one modifier key to the custom hotkey."
            case .missingMainKey:
                return "Choose a main key for the custom hotkey."
            case .reservedRightCommand:
                return "Right Command is reserved for the built-in hotkey mode."
            case .valid:
                return "Choose a valid custom hotkey."
            }
        case .registrationFailed:
            return "The custom hotkey could not be registered. It may already be in use."
        }
    }
}
