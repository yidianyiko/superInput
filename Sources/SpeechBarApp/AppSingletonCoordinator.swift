import AppKit
import Foundation

private func singletonLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Singleton] \(message)\n"
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

@MainActor
protocol RunningApplicationControlling: AnyObject {
    var processIdentifier: pid_t { get }
    var bundleIdentifier: String? { get }
    var isTerminated: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

extension NSRunningApplication: RunningApplicationControlling {}

@MainActor
struct AppSingletonCoordinator {
    let runningApplicationsProvider: (String) -> [any RunningApplicationControlling]
    let scheduleAfter: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    let logger: (String) -> Void

    init(
        runningApplicationsProvider: @escaping (String) -> [any RunningApplicationControlling] = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        },
        scheduleAfter: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
            let delayMilliseconds = max(0, Int((delay * 1_000).rounded()))
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                action()
            }
        },
        logger: @escaping (String) -> Void = singletonLog
    ) {
        self.runningApplicationsProvider = runningApplicationsProvider
        self.scheduleAfter = scheduleAfter
        self.logger = logger
    }

    func terminateOtherInstances(
        bundleIdentifier: String?,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        gracePeriod: TimeInterval = 0.4
    ) {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return
        }

        let otherInstances = runningApplicationsProvider(bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }
        guard !otherInstances.isEmpty else { return }

        logger("found \(otherInstances.count) existing instance(s) for \(bundleIdentifier)")

        for application in otherInstances {
            _ = application.terminate()
            logger("sent terminate to pid=\(application.processIdentifier)")
        }

        let remainingAfterTerminate = otherInstances.filter { !$0.isTerminated }
        guard !remainingAfterTerminate.isEmpty else { return }

        let remainingProcessIdentifiers = Set(remainingAfterTerminate.map(\.processIdentifier))

        scheduleAfter(gracePeriod) {
            let remainingInstances = runningApplicationsProvider(bundleIdentifier)
                .filter { $0.processIdentifier != currentProcessIdentifier }
                .filter { remainingProcessIdentifiers.contains($0.processIdentifier) }

            for application in remainingInstances where !application.isTerminated {
                _ = application.forceTerminate()
                logger("force terminated pid=\(application.processIdentifier)")
            }
        }
    }
}
