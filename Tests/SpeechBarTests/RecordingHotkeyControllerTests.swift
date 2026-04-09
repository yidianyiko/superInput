import Carbon.HIToolbox
import Foundation
import Testing
@testable import SpeechBarInfrastructure
import SpeechBarDomain

@Suite("RecordingHotkeyController", .serialized)
struct RecordingHotkeyControllerTests {
    @Test
    func switchingModesRebuildsTheActiveListenerAndTracksLastTrigger() async throws {
        let sourceRecorder = RecordingHotkeySourceRecorder()

        let customConfiguration = RecordingHotkeyConfiguration(
            mode: .customCombo,
            customCombination: RecordingHotkeyCombination(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            )
        )

        let controller = RecordingHotkeyController(
            configuration: RecordingHotkeyConfiguration.defaultRightCommand,
            rightCommandSourceFactory: {
                let source = MockRecordingHotkeyRuntimeSource(
                    diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot(
                        configuration: RecordingHotkeyConfiguration.defaultRightCommand,
                        registrationStatus: .registered,
                        requiresAccessibility: true,
                        accessibilityTrusted: true,
                        lastTrigger: nil,
                        guidanceText: nil
                    )
                )
                sourceRecorder.appendRightCommand(source)
                return source
            },
            customComboSourceFactory: { configuration in
                let source = MockRecordingHotkeyRuntimeSource(
                    diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot(
                        configuration: configuration,
                        registrationStatus: .registered,
                        requiresAccessibility: false,
                        accessibilityTrusted: true,
                        lastTrigger: nil,
                        guidanceText: nil
                    )
                )
                sourceRecorder.appendCustom(source)
                return source
            }
        )

        #expect(sourceRecorder.rightCommandCount == 1)
        #expect(sourceRecorder.customCount == 0)
        #expect(controller.diagnosticsSnapshot.configuration == RecordingHotkeyConfiguration.defaultRightCommand)

        let rightCommandSource = try #require(sourceRecorder.firstRightCommand)
        #expect(rightCommandSource.shutdownCallCount == 0)
        let firstEventTask = Task {
            try await collectHardwareEvents(from: controller.events, count: 1)
        }
        let diagnosticsTask = Task<[RecordingHotkeyDiagnosticsSnapshot], Error> {
            try await collectDiagnosticsSnapshots(from: controller.diagnosticsUpdates, count: 5)
        }
        await Task.yield()

        let pressedAt = Date(timeIntervalSinceReferenceDate: 100)
        rightCommandSource.send(
            HardwareEvent(
                source: .globalRightCommandKey,
                kind: .pushToTalkPressed,
                occurredAt: pressedAt
            )
        )

        let firstEvents = try await firstEventTask.value
        #expect(firstEvents.map(\.kind) == [HardwareEventKind.pushToTalkPressed])
        #expect(
            controller.diagnosticsSnapshot.lastTrigger == RecordingHotkeyLastTrigger(
                occurredAt: pressedAt,
                mode: .rightCommand,
                action: .start
            )
        )

        controller.apply(customConfiguration)

        #expect(sourceRecorder.rightCommandCount == 1)
        #expect(sourceRecorder.customCount == 1)
        #expect(rightCommandSource.shutdownCallCount == 1)
        #expect(controller.diagnosticsSnapshot.configuration == customConfiguration)
        #expect(
            controller.diagnosticsSnapshot.lastTrigger == RecordingHotkeyLastTrigger(
                occurredAt: pressedAt,
                mode: .rightCommand,
                action: .start
            )
        )

        let switchedEventTask = Task {
            try await collectHardwareEvents(from: controller.events, count: 1)
        }
        rightCommandSource.send(
            HardwareEvent(
                source: .globalRightCommandKey,
                kind: .pushToTalkReleased,
                occurredAt: Date(timeIntervalSinceReferenceDate: 101)
            )
        )

        let customSource = try #require(sourceRecorder.firstCustom)
        let releasedAt = Date(timeIntervalSinceReferenceDate: 102)
        customSource.send(
            HardwareEvent(
                source: .globalShortcut,
                kind: .pushToTalkReleased,
                occurredAt: releasedAt
            )
        )
        customSource.updateDiagnostics(
            RecordingHotkeyDiagnosticsSnapshot(
                configuration: customConfiguration,
                registrationStatus: .registrationFailed,
                requiresAccessibility: false,
                accessibilityTrusted: true,
                lastTrigger: nil,
                guidanceText: "The custom hotkey could not be registered. It may already be in use."
            )
        )

        let switchedEvents = try await switchedEventTask.value
        let diagnosticsSnapshots = try await diagnosticsTask.value
        #expect(switchedEvents.map(\.source) == [HardwareSourceKind.globalShortcut])
        #expect(switchedEvents.map(\.kind) == [HardwareEventKind.pushToTalkReleased])
        #expect(
            controller.diagnosticsSnapshot.lastTrigger == RecordingHotkeyLastTrigger(
                occurredAt: releasedAt,
                mode: .customCombo,
                action: .stop
            )
        )
        #expect(
            Array(diagnosticsSnapshots.prefix(3)) == [
                RecordingHotkeyDiagnosticsSnapshot(
                    configuration: RecordingHotkeyConfiguration.defaultRightCommand,
                    registrationStatus: .registered,
                    requiresAccessibility: true,
                    accessibilityTrusted: true,
                    lastTrigger: nil,
                    guidanceText: nil
                ),
                RecordingHotkeyDiagnosticsSnapshot(
                    configuration: RecordingHotkeyConfiguration.defaultRightCommand,
                    registrationStatus: .registered,
                    requiresAccessibility: true,
                    accessibilityTrusted: true,
                    lastTrigger: RecordingHotkeyLastTrigger(
                        occurredAt: pressedAt,
                        mode: .rightCommand,
                        action: .start
                    ),
                    guidanceText: nil
                ),
                RecordingHotkeyDiagnosticsSnapshot(
                    configuration: customConfiguration,
                    registrationStatus: .registered,
                    requiresAccessibility: false,
                    accessibilityTrusted: true,
                    lastTrigger: RecordingHotkeyLastTrigger(
                        occurredAt: pressedAt,
                        mode: .rightCommand,
                        action: .start
                    ),
                    guidanceText: nil
                ),
            ]
        )
        #expect(diagnosticsSnapshots.count == 5)
        #expect(
            diagnosticsSnapshots.contains(
                RecordingHotkeyDiagnosticsSnapshot(
                    configuration: customConfiguration,
                    registrationStatus: .registered,
                    requiresAccessibility: false,
                    accessibilityTrusted: true,
                    lastTrigger: RecordingHotkeyLastTrigger(
                        occurredAt: releasedAt,
                        mode: .customCombo,
                        action: .stop
                    ),
                    guidanceText: nil
                )
            )
        )
        #expect(
            diagnosticsSnapshots.contains(
                RecordingHotkeyDiagnosticsSnapshot(
                    configuration: customConfiguration,
                    registrationStatus: .registrationFailed,
                    requiresAccessibility: false,
                    accessibilityTrusted: true,
                    lastTrigger: RecordingHotkeyLastTrigger(
                        occurredAt: releasedAt,
                        mode: .customCombo,
                        action: .stop
                    ),
                    guidanceText: "The custom hotkey could not be registered. It may already be in use."
                )
            )
        )
    }

    @Test
    func rightCommandPermissionRequirementSurfacesInDiagnostics() {
        let expectedGuidance = "Grant Accessibility access to use the right Command hotkey."
        let controller = RecordingHotkeyController(
            configuration: RecordingHotkeyConfiguration.defaultRightCommand,
            rightCommandSourceFactory: {
                MockRecordingHotkeyRuntimeSource(
                    diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot(
                        configuration: RecordingHotkeyConfiguration.defaultRightCommand,
                        registrationStatus: .permissionRequired,
                        requiresAccessibility: true,
                        accessibilityTrusted: false,
                        lastTrigger: nil,
                        guidanceText: expectedGuidance
                    )
                )
            },
            customComboSourceFactory: { configuration in
                MockRecordingHotkeyRuntimeSource(
                    diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot(
                        configuration: configuration,
                        registrationStatus: .registered,
                        requiresAccessibility: false,
                        accessibilityTrusted: true,
                        lastTrigger: nil,
                        guidanceText: nil
                    )
                )
            }
        )

        let diagnostics = controller.diagnosticsSnapshot
        #expect(diagnostics.configuration == RecordingHotkeyConfiguration.defaultRightCommand)
        #expect(diagnostics.registrationStatus == RecordingHotkeyRegistrationStatus.permissionRequired)
        #expect(diagnostics.requiresAccessibility)
        #expect(!diagnostics.accessibilityTrusted)
        #expect(diagnostics.guidanceText == expectedGuidance)
    }

    @Test
    func rightCommandSourceDoesNotPublishBufferedInitialDiagnosticsWhenStartupSucceeds() async {
        let harness = RightCommandSourceTestHarness(accessibilityTrusted: true)
        let source = harness.makeSource()

        #expect(
            source.diagnosticsSnapshot == RecordingHotkeyDiagnosticsSnapshot(
                configuration: .defaultRightCommand,
                registrationStatus: .registered,
                requiresAccessibility: true,
                accessibilityTrusted: true,
                lastTrigger: nil,
                guidanceText: nil
            )
        )

        await #expect(throws: RecordingHotkeyControllerTestFailure.self) {
            try await collectDiagnosticsSnapshots(
                from: source.diagnosticsUpdates,
                count: 1,
                timeout: .milliseconds(100)
            )
        }
    }

    @Test
    func rightCommandSourceDoesNotInstallATapAfterShutdownWinsTheRetryRace() async throws {
        let harness = RightCommandSourceTestHarness(
            accessibilityTrusted: false,
            blockEventTapCreation: true
        )
        let source = harness.makeSource()

        #expect(source.diagnosticsSnapshot.registrationStatus == .permissionRequired)
        #expect(harness.retryDriver.installAttemptCount == 1)

        harness.setAccessibilityTrusted(true)
        let retryTask = Task {
            harness.retryDriver.fire()
        }
        try await harness.waitUntilEventTapCreationStarts()

        source.shutdown()
        harness.releaseBlockedEventTapCreation()
        await retryTask.value

        #expect(harness.addRunLoopSourceCallCount == 0)
        #expect(harness.enableEventTapCallCount == 0)
        #expect(harness.invalidateEventTapCallCount == 1)
    }
}

private func collectHardwareEvents(
    from stream: AsyncStream<HardwareEvent>,
    count: Int
) async throws -> [HardwareEvent] {
    try await withThrowingTaskGroup(of: [HardwareEvent].self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            var events: [HardwareEvent] = []

            while events.count < count, let event = await iterator.next() {
                events.append(event)
            }

            return events
        }

        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw RecordingHotkeyControllerTestFailure.timeout
        }

        let result = try await group.next() ?? []
        group.cancelAll()
        return result
    }
}

private func collectDiagnosticsSnapshots(
    from stream: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>,
    count: Int,
    timeout: Duration = .seconds(1)
) async throws -> [RecordingHotkeyDiagnosticsSnapshot] {
    try await withThrowingTaskGroup(of: [RecordingHotkeyDiagnosticsSnapshot].self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            var snapshots: [RecordingHotkeyDiagnosticsSnapshot] = []

            while snapshots.count < count, let snapshot = await iterator.next() {
                snapshots.append(snapshot)
            }

            return snapshots
        }

        group.addTask {
            try await Task.sleep(for: timeout)
            throw RecordingHotkeyControllerTestFailure.timeout
        }

        let result = try await group.next() ?? []
        group.cancelAll()
        return result
    }
}

private enum RecordingHotkeyControllerTestFailure: Error {
    case timeout
}

private final class RecordingHotkeySourceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rightCommandSources: [MockRecordingHotkeyRuntimeSource] = []
    private var customSources: [MockRecordingHotkeyRuntimeSource] = []

    func appendRightCommand(_ source: MockRecordingHotkeyRuntimeSource) {
        lock.lock()
        rightCommandSources.append(source)
        lock.unlock()
    }

    func appendCustom(_ source: MockRecordingHotkeyRuntimeSource) {
        lock.lock()
        customSources.append(source)
        lock.unlock()
    }

    var rightCommandCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rightCommandSources.count
    }

    var customCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return customSources.count
    }

    var firstRightCommand: MockRecordingHotkeyRuntimeSource? {
        lock.lock()
        defer { lock.unlock() }
        return rightCommandSources.first
    }

    var firstCustom: MockRecordingHotkeyRuntimeSource? {
        lock.lock()
        defer { lock.unlock() }
        return customSources.first
    }
}

private final class RightCommandSourceTestHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var accessibilityTrusted: Bool
    private let blockEventTapCreation: Bool
    private let allowCreationToFinish = DispatchSemaphore(value: 0)
    private var eventTapCreationStarted = false

    let retryDriver = MockRightCommandRetryDriver()

    private(set) var addRunLoopSourceCallCount = 0
    private(set) var enableEventTapCallCount = 0
    private(set) var invalidateEventTapCallCount = 0

    init(accessibilityTrusted: Bool, blockEventTapCreation: Bool = false) {
        self.accessibilityTrusted = accessibilityTrusted
        self.blockEventTapCreation = blockEventTapCreation
    }

    func makeSource() -> GlobalRightCommandPushToTalkSource {
        GlobalRightCommandPushToTalkSource(
            dependencies: .init(
                isAccessibilityTrusted: { [weak self] in
                    self?.snapshotAccessibilityTrusted() ?? false
                },
                promptForAccessibilityIfNeeded: {},
                createEventTap: { [weak self] _, _ in
                    self?.markEventTapCreationStarted()
                    if self?.blockEventTapCreation == true {
                        self?.allowCreationToFinish.wait()
                    }
                    return Self.makeTestEventTap()
                },
                makeRunLoopSource: { _ in
                    Self.makeTestRunLoopSource()
                },
                addRunLoopSource: { [weak self] _ in
                    self?.lock.lock()
                    self?.addRunLoopSourceCallCount += 1
                    self?.lock.unlock()
                },
                removeRunLoopSource: { _ in },
                enableEventTap: { [weak self] _ in
                    self?.lock.lock()
                    self?.enableEventTapCallCount += 1
                    self?.lock.unlock()
                },
                invalidateEventTap: { [weak self] eventTap in
                    self?.lock.lock()
                    self?.invalidateEventTapCallCount += 1
                    self?.lock.unlock()
                    CFMachPortInvalidate(eventTap)
                },
                createRetryTimer: { [retryDriver] action in
                    retryDriver.makeTimer(action: action)
                }
            )
        )
    }

    func setAccessibilityTrusted(_ value: Bool) {
        lock.lock()
        accessibilityTrusted = value
        lock.unlock()
    }

    func waitUntilEventTapCreationStarts() async throws {
        for _ in 0..<100 {
            if snapshotEventTapCreationStarted() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw RecordingHotkeyControllerTestFailure.timeout
    }

    func releaseBlockedEventTapCreation() {
        allowCreationToFinish.signal()
    }

    private func snapshotAccessibilityTrusted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return accessibilityTrusted
    }

    private func snapshotEventTapCreationStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTapCreationStarted
    }

    private func markEventTapCreationStarted() {
        lock.lock()
        eventTapCreationStarted = true
        lock.unlock()
    }

    private static func makeTestEventTap() -> CFMachPort? {
        var shouldFreeInfo = DarwinBoolean(false)
        var context = CFMachPortContext()
        return CFMachPortCreate(
            kCFAllocatorDefault,
            { _, _, _, _ in },
            &context,
            &shouldFreeInfo
        )
    }

    private static func makeTestRunLoopSource() -> CFRunLoopSource {
        var context = CFRunLoopSourceContext()
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)
    }
}

private final class MockRightCommandRetryDriver: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private(set) var installAttemptCount = 0

    func makeTimer(action: @escaping @Sendable () -> Void) -> any GlobalRightCommandRetryTimer {
        lock.lock()
        self.action = action
        installAttemptCount += 1
        lock.unlock()
        return MockRightCommandRetryTimer()
    }

    func fire() {
        lock.lock()
        let action = self.action
        lock.unlock()
        action?()
    }
}

private final class MockRightCommandRetryTimer: GlobalRightCommandRetryTimer, @unchecked Sendable {
    private(set) var invalidateCallCount = 0

    func invalidate() {
        invalidateCallCount += 1
    }
}
