import AppKit
import Combine
import SpeechBarDomain
import SwiftUI

@MainActor
final class WindowSwitchOverlayController: NSObject {
    private let panel: NSPanel
    private let store: WindowSwitchOverlayStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: WindowSwitchOverlayStore) {
        self.store = store

        let hostingController = NSHostingController(
            rootView: WindowSwitchOverlayView(store: store)
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 126),
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

        super.init()
        bindStore()
    }

    private func bindStore() {
        Publishers.CombineLatest3(store.$isVisible, store.$items, store.$selectedIndex)
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible, items, selectedIndex in
                self?.handleStateChange(isVisible: isVisible, items: items, selectedIndex: selectedIndex)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(
        isVisible: Bool,
        items: [WindowSwitchPreviewItem],
        selectedIndex: Int
    ) {
        guard isVisible, !items.isEmpty else {
            hidePanel()
            return
        }

        resizePanel(for: items, selectedIndex: selectedIndex)
        showPanel()
    }

    private func showPanel() {
        repositionPanel()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        })
    }

    private func resizePanel(for items: [WindowSwitchPreviewItem], selectedIndex: Int) {
        let count = visibleItems(items: items, selectedIndex: selectedIndex).count
        let width = max(430, CGFloat(count) * 100 + 42)
        panel.setContentSize(NSSize(width: width, height: 126))
        repositionPanel()
    }

    private func repositionPanel() {
        guard let screen = currentScreen() ?? NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.frame.midX - frame.width / 2
        let y = screen.frame.midY - frame.height / 2 + 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func visibleItems(
        items: [WindowSwitchPreviewItem],
        selectedIndex: Int
    ) -> [WindowSwitchPreviewItem] {
        guard items.count > 7 else { return items }
        let lowerBound = max(0, min(selectedIndex - 3, items.count - 7))
        let upperBound = min(items.count, lowerBound + 7)
        return Array(items[lowerBound..<upperBound])
    }
}

private struct WindowSwitchOverlayView: View {
    @ObservedObject var store: WindowSwitchOverlayStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.item.id) { entry in
                let element = entry.element
                WindowSwitchIconCell(
                    title: shortLabel(for: element.item),
                    isSelected: element.isSelected,
                    icon: appIcon(for: element.item)
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            backgroundShape
                .fill(.ultraThinMaterial)
                .overlay {
                    backgroundShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.34),
                                    Color.black.opacity(0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
        }
        .clipShape(backgroundShape)
        .overlay {
            backgroundShape
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            backgroundShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(1)
        }
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
    }

    private var visibleEntries: [(item: WindowSwitchPreviewItem, isSelected: Bool)] {
        guard !store.items.isEmpty else { return [] }

        let selectedIndex = min(max(store.selectedIndex, 0), store.items.count - 1)
        let lowerBound = max(0, min(selectedIndex - 3, max(store.items.count - 7, 0)))
        let upperBound = min(store.items.count, lowerBound + 7)
        let range = lowerBound..<upperBound

        return range.map { index in
            (
                item: store.items[index],
                isSelected: index == selectedIndex
            )
        }
    }

    private func shortLabel(for item: WindowSwitchPreviewItem) -> String {
        let trimmed = item.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "App" }
        if trimmed.count <= 8 {
            return trimmed
        }
        return String(trimmed.prefix(7)) + "…"
    }

    private func appIcon(for item: WindowSwitchPreviewItem) -> NSImage? {
        if let application = NSRunningApplication(processIdentifier: item.processIdentifier),
           let icon = application.icon {
            return icon
        }

        if let bundleIdentifier = item.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
    }
}

private struct WindowSwitchIconCell: View {
    let title: String
    let isSelected: Bool
    let icon: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.34),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.32), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
                }

                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: isSelected ? 72 : 68, height: isSelected ? 72 : 68)
                        .shadow(color: Color.black.opacity(isSelected ? 0.2 : 0.1), radius: 5, x: 0, y: 2)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: isSelected ? 39 : 36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                }
            }
            .frame(width: 88, height: 88)

            if isSelected {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .frame(width: 88)
        .opacity(isSelected ? 1 : 0.84)
        .scaleEffect(isSelected ? 1 : 0.94)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
