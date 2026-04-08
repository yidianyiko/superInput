import Darwin
import Testing
@testable import SpeechBarApp

@Suite("AppSingletonCoordinator")
struct AppSingletonCoordinatorTests {
    @Test
    @MainActor
    func terminatesAndForceTerminatesOtherInstances() {
        let current = MockRunningApplication(processIdentifier: 100, bundleIdentifier: "com.slashvibe.desktop.local")
        let lingering = MockRunningApplication(processIdentifier: 200, bundleIdentifier: "com.slashvibe.desktop.local")
        var sleepCalls = 0
        let coordinator = AppSingletonCoordinator(
            runningApplicationsProvider: { _ in [current, lingering] },
            sleep: { _ in sleepCalls += 1 },
            logger: { _ in }
        )

        coordinator.terminateOtherInstances(
            bundleIdentifier: "com.slashvibe.desktop.local",
            currentProcessIdentifier: 100
        )

        #expect(current.terminateCallCount == 0)
        #expect(current.forceTerminateCallCount == 0)
        #expect(lingering.terminateCallCount == 1)
        #expect(lingering.forceTerminateCallCount == 1)
        #expect(sleepCalls == 1)
    }

    @Test
    @MainActor
    func doesNotForceTerminateWhenAppExitsAfterTerminate() {
        let exiting = MockRunningApplication(
            processIdentifier: 200,
            bundleIdentifier: "com.slashvibe.desktop.local",
            terminateBehavior: { app in
                app.markTerminated()
            }
        )
        var sleepCalls = 0
        let coordinator = AppSingletonCoordinator(
            runningApplicationsProvider: { _ in [exiting] },
            sleep: { _ in sleepCalls += 1 },
            logger: { _ in }
        )

        coordinator.terminateOtherInstances(
            bundleIdentifier: "com.slashvibe.desktop.local",
            currentProcessIdentifier: 100
        )

        #expect(exiting.terminateCallCount == 1)
        #expect(exiting.forceTerminateCallCount == 0)
        #expect(sleepCalls == 0)
    }

    @Test
    @MainActor
    func ignoresMissingBundleIdentifier() {
        var providerCalls = 0
        let coordinator = AppSingletonCoordinator(
            runningApplicationsProvider: { _ in
                providerCalls += 1
                return []
            },
            sleep: { _ in
                Issue.record("sleep should not be called")
            },
            logger: { _ in }
        )

        coordinator.terminateOtherInstances(
            bundleIdentifier: nil,
            currentProcessIdentifier: 100
        )

        #expect(providerCalls == 0)
    }
}

@MainActor
private final class MockRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    private(set) var isTerminated: Bool
    private let terminateBehavior: (MockRunningApplication) -> Void
    private(set) var terminateCallCount = 0
    private(set) var forceTerminateCallCount = 0

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        isTerminated: Bool = false,
        terminateBehavior: @escaping (MockRunningApplication) -> Void = { _ in }
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.isTerminated = isTerminated
        self.terminateBehavior = terminateBehavior
    }

    func terminate() -> Bool {
        terminateCallCount += 1
        terminateBehavior(self)
        return true
    }

    func forceTerminate() -> Bool {
        forceTerminateCallCount += 1
        isTerminated = true
        return true
    }

    func markTerminated() {
        isTerminated = true
    }
}
