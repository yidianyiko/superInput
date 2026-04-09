import AppKit
import SpeechBarApplication
import SpeechBarDomain
import SwiftUI

@MainActor
final class TranscriptInjectionOverlayController: NSObject {
    private let panel: NSPanel
    private let store = TranscriptInjectionOverlayStore()
    private let targetProvider: any TranscriptInjectionTargetSnapshotProviding
    private let sleepClock: any SleepClock
    private let visibleDuration: Duration
    private var feedbackTask: Task<Void, Never>?
    private var scheduledHideTask: Task<Void, Never>?

    init(
        coordinator: VoiceSessionCoordinator,
        targetProvider: any TranscriptInjectionTargetSnapshotProviding,
        sleepClock: any SleepClock = ContinuousSleepClock(),
        visibleDuration: Duration = .milliseconds(700)
    ) {
        self.targetProvider = targetProvider
        self.sleepClock = sleepClock
        self.visibleDuration = visibleDuration

        let hostingController = NSHostingController(
            rootView: TranscriptInjectionOverlayView(store: store)
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        panel.orderOut(nil)
        self.panel = panel

        let events = coordinator.publishFeedbackNotifier.events

        super.init()

        feedbackTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    deinit {
        feedbackTask?.cancel()
        scheduledHideTask?.cancel()
    }

    private func handle(_ event: TranscriptPublishFeedbackEvent) async {
        switch event {
        case .started(let start):
            guard let target = await targetProvider.currentTranscriptInjectionTargetSnapshot() else {
                return
            }

            scheduledHideTask?.cancel()
            scheduledHideTask = nil
            store.start(
                publishID: start.publishID,
                target: target,
                startedAt: start.createdAt
            )
            panel.setFrame(target.screenFrame, display: false)
            showPanel()
            scheduleHide(for: start.publishID)

        case .completed(let completion):
            store.complete(
                publishID: completion.publishID,
                outcome: completion.outcome
            )

            if completion.outcome == .publishedOnly {
                hidePanel()
            }

        case .failed(let failure):
            scheduledHideTask?.cancel()
            scheduledHideTask = nil
            store.clear(publishID: failure.publishID)
            hidePanel()
        }
    }

    private func scheduleHide(for publishID: UUID) {
        scheduledHideTask?.cancel()
        scheduledHideTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await sleepClock.sleep(for: visibleDuration)
            } catch {
                return
            }

            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard self.store.activePublishID == publishID else {
                    return
                }
                self.store.clear(publishID: publishID)
                self.hidePanel()
            }
        }
    }

    private func showPanel() {
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        })
    }

    var activePublishIDForTesting: UUID? {
        store.activePublishID
    }

    var endingStyleForTesting: TranscriptInjectionOverlayEndingStyle? {
        store.presentation?.endingStyle
    }

    var panelFrameForTesting: CGRect {
        panel.frame
    }

    var panelIsVisibleForTesting: Bool {
        panel.isVisible
    }

    var panelIgnoresMouseEventsForTesting: Bool {
        panel.ignoresMouseEvents
    }
}
