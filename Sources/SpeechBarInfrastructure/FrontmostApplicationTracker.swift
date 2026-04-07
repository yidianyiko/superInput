import AppKit
import Foundation

@MainActor
public final class FrontmostApplicationTracker: NSObject {
    private var lastExternalApplication: NSRunningApplication?
    private var recentExternalProcessIDs: [pid_t] = []

    public override init() {
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApplication = frontmost
            markRecent(frontmost.processIdentifier)
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func handleActivation(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let currentBundleID = Bundle.main.bundleIdentifier
        else {
            return
        }

        if app.bundleIdentifier != currentBundleID {
            lastExternalApplication = app
            markRecent(app.processIdentifier)
        }
    }

    public func activateLastExternalApplication() -> Bool {
        guard let application = lastExternalApplication else {
            return false
        }

        return application.activate(options: [.activateIgnoringOtherApps])
    }

    public func activate(processIdentifier: pid_t) -> Bool {
        guard let application = application(processIdentifier: processIdentifier) else {
            return false
        }

        lastExternalApplication = application
        markRecent(processIdentifier)
        return application.activate(options: [.activateIgnoringOtherApps])
    }

    public func application(processIdentifier: pid_t) -> NSRunningApplication? {
        if let lastExternalApplication,
           lastExternalApplication.processIdentifier == processIdentifier {
            return lastExternalApplication
        }

        return NSRunningApplication(processIdentifier: processIdentifier)
    }

    public func lastExternalProcessIdentifier() -> pid_t? {
        lastExternalApplication?.processIdentifier
    }

    public func recentExternalApplications() -> [NSRunningApplication] {
        recentExternalProcessIDs.compactMap { processIdentifier in
            guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
                return nil
            }
            guard !application.isTerminated else {
                return nil
            }
            guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return nil
            }
            return application
        }
    }

    private func markRecent(_ processIdentifier: pid_t) {
        recentExternalProcessIDs.removeAll { $0 == processIdentifier }
        recentExternalProcessIDs.insert(processIdentifier, at: 0)
        if recentExternalProcessIDs.count > 24 {
            recentExternalProcessIDs.removeLast(recentExternalProcessIDs.count - 24)
        }
    }
}
