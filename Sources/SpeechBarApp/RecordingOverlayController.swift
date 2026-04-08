import AppKit
import Combine
import SpeechBarApplication
import SpeechBarDomain
import SwiftUI

@MainActor
final class RecordingOverlayController: NSObject {
    private let panel: NSPanel
    private let coordinator: VoiceSessionCoordinator
    private var cancellables: Set<AnyCancellable> = []
    private var scheduledHideTask: Task<Void, Never>?

    init(coordinator: VoiceSessionCoordinator) {
        self.coordinator = coordinator

        let hostingController = NSHostingController(
            rootView: RecordingOverlayView(coordinator: coordinator)
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 194, height: 50),
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
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.orderOut(nil)
        self.panel = panel

        super.init()
        bindCoordinator()
    }

    private func bindCoordinator() {
        coordinator.$overlayPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handleOverlayPhaseChange(phase)
            }
            .store(in: &cancellables)
    }

    private func handleOverlayPhaseChange(_ phase: RecordingOverlayPhase) {
        scheduledHideTask?.cancel()
        scheduledHideTask = nil
        resizePanel(for: phase)

        switch phase {
        case .hidden:
            hidePanel(animated: true)

        case .failed:
            showPanel()
            scheduledHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1400))
                await MainActor.run {
                    guard self?.coordinator.overlayPhase == .failed else { return }
                    self?.hidePanel(animated: true)
                }
            }

        case .recording, .finalizing, .polishing, .publishing:
            showPanel()
        }
    }

    private func showPanel() {
        repositionPanel()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hidePanel(animated: Bool) {
        guard panel.isVisible else { return }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.panel.orderOut(nil)
                    self?.panel.alphaValue = 1
                }
            })
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func repositionPanel() {
        let targetScreen = currentScreen() ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let frame = panel.frame
        let x = screen.frame.midX - frame.width / 2
        let y = screen.frame.minY + 34
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func resizePanel(for phase: RecordingOverlayPhase) {
        let size = panelSize(for: phase)
        guard panel.contentView?.frame.size != size else { return }
        panel.setContentSize(size)
        repositionPanel()
    }

    private func panelSize(for phase: RecordingOverlayPhase) -> NSSize {
        switch phase {
        case .recording:
            NSSize(width: 172, height: 52)
        case .finalizing, .polishing, .publishing:
            NSSize(width: 132, height: 40)
        case .failed:
            NSSize(width: 152, height: 42)
        case .hidden:
            NSSize(width: 132, height: 40)
        }
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

struct RecordingOverlayView: View {
    struct DecorativeState: Equatable {
        let shouldAnimateTimeline: Bool
        let decorativeIntensity: Double
    }

    nonisolated static let reducedMotionDecorativeIntensity = 0.22

    nonisolated static func decorativeState(
        overlayPhase: RecordingOverlayPhase,
        reduceMotion: Bool,
        samples: [AudioLevelSample]
    ) -> DecorativeState {
        let isRecording = overlayPhase == .recording
        return DecorativeState(
            shouldAnimateTimeline: isRecording && !reduceMotion,
            decorativeIntensity: reduceMotion
                ? reducedMotionDecorativeIntensity
                : RecordingOverlayMotion.audioIntensity(from: samples)
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: VoiceSessionCoordinator

    var body: some View {
        let decorativeState = Self.decorativeState(
            overlayPhase: coordinator.overlayPhase,
            reduceMotion: reduceMotion,
            samples: coordinator.audioLevelWindow
        )

        return TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !decorativeState.shouldAnimateTimeline)) { context in
            let phase = decorativeState.shouldAnimateTimeline ? context.date.timeIntervalSinceReferenceDate : 0

            if coordinator.overlayPhase == .recording {
                recordingPill(phase: phase, decorativeIntensity: decorativeState.decorativeIntensity)
                    .frame(width: pillWidth, height: pillHeight)
                    .background(Color.clear)
            } else {
                statusPill
                    .frame(width: pillWidth, height: pillHeight)
                    .clipShape(Capsule(style: .continuous))
                    .background(Color.clear)
            }
        }
    }

    private var title: String {
        switch coordinator.overlayPhase {
        case .recording:
            return ""
        case .finalizing, .polishing, .publishing:
            return "Thinking"
        case .failed:
            return "Try again"
        case .hidden:
            return ""
        }
    }

    private var pillWidth: CGFloat {
        switch coordinator.overlayPhase {
        case .recording:
            172
        case .finalizing, .polishing, .publishing:
            132
        case .failed:
            152
        case .hidden:
            132
        }
    }

    private var pillHeight: CGFloat {
        switch coordinator.overlayPhase {
        case .recording:
            52
        case .finalizing, .polishing, .publishing:
            40
        case .failed:
            42
        case .hidden:
            40
        }
    }

    private func recordingPill(phase: TimeInterval, decorativeIntensity: Double) -> some View {
        let glowOpacity = RecordingOverlayMotion.edgeGlowOpacity(intensity: decorativeIntensity)
        let glowRadius = 4.5 + (decorativeIntensity * 6.0)

        return ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.95))
                .overlay(recordingBackground(phase: phase, decorativeIntensity: decorativeIntensity))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            Color(red: 0.58, green: 0.93, blue: 0.82).opacity(glowOpacity),
                            lineWidth: 1.1
                        )
                        .blur(radius: glowRadius)
                )
                .shadow(
                    color: Color(red: 0.48, green: 0.88, blue: 0.78).opacity(glowOpacity * 0.65),
                    radius: glowRadius,
                    x: 0,
                    y: 0
                )

            HStack(spacing: 10) {
                actionButton(
                    systemName: "xmark",
                    foreground: .white.opacity(0.92),
                    background: Color.white.opacity(0.17)
                ) {
                    coordinator.cancelCaptureFromOverlay()
                }

                WaveformBars(samples: coordinator.audioLevelWindow)
                    .frame(width: 42, height: 14)

                actionButton(
                    systemName: "checkmark",
                    foreground: .black.opacity(0.92),
                    background: .white
                ) {
                    coordinator.finalizeCaptureFromOverlay()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
    }

    private func recordingBackground(phase: TimeInterval, decorativeIntensity: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let nebulaOpacity = 0.16 + (decorativeIntensity * 0.24)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.14, blue: 0.18).opacity(0.82),
                        Color.black.opacity(0.30)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.60, green: 0.92, blue: 0.83).opacity(nebulaOpacity),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 64
                )

                ForEach(Array(RecordingOverlayMotion.ambientStars.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let star = item.element
                    let offset = reduceMotion
                        ? .zero
                        : RecordingOverlayMotion.starOffset(index: index, phase: phase, intensity: decorativeIntensity)
                    let twinkle = (sin((phase * 1.45) + (star.seed * 2.2)) + 1) * 0.5
                    let starOpacity = min(0.78, 0.20 + (decorativeIntensity * 0.22) + (twinkle * 0.22))

                    Circle()
                        .fill(Color.white.opacity(starOpacity))
                        .frame(width: star.size, height: star.size)
                        .position(
                            x: (star.x * size.width) + offset.width,
                            y: (star.y * size.height) + offset.height
                        )
                }
            }
            .clipShape(Capsule(style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var statusPill: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(red: 0.24, green: 0.24, blue: 0.24).opacity(0.96))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )

            HStack {
                Spacer(minLength: 0)
                Circle()
                    .fill(Color.black.opacity(0.96))
                    .frame(width: 38, height: 38)
                    .overlay {
                        if coordinator.overlayPhase == .failed {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            ThinkingDots()
                                .frame(width: 16, height: 8)
                        }
                    }
                    .padding(.trailing, 1)
            }

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.trailing, 18)
        }
    }

    private func actionButton(
        systemName: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            OverlayOrb(
                systemName: systemName,
                foreground: foreground,
                background: background,
                size: 31,
                iconSize: 13
            )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

private struct OverlayOrb: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(foreground)
            }
    }
}

private struct WaveformBars: View {
    let samples: [AudioLevelSample]

    var body: some View {
        let bars = samples.suffix(7)

        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { item in
                let sample = item.element
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color(red: 0.54, green: 0.94, blue: 0.75)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 2.2, height: max(4, CGFloat(sample.level) * 11))
            }

            if bars.isEmpty {
                ForEach(0..<7, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 2.2, height: 4)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct ThinkingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.84))
                    .frame(width: 4, height: 4)
                    .scaleEffect(isAnimating ? 1 : 0.55)
                    .opacity(isAnimating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
