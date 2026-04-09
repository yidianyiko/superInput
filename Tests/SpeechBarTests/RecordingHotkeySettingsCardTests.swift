import AppKit
import Testing
@testable import SpeechBarApp

@Suite("RecordingHotkeySettingsCard")
struct RecordingHotkeySettingsCardTests {
    @Test
    @MainActor
    func captureViewRestoresPreviousFirstResponderWhenCaptureStops() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView!.bounds)
        let previousResponder = FocusProbeView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        let captureView = RecordingHotkeyCaptureNSView(frame: NSRect(x: 0, y: 50, width: 120, height: 40))

        container.addSubview(previousResponder)
        container.addSubview(captureView)
        window.contentView = container

        #expect(window.makeFirstResponder(previousResponder))

        captureView.isActive = true
        try await Task.sleep(for: .milliseconds(20))
        #expect(window.firstResponder === captureView)

        captureView.isActive = false
        try await Task.sleep(for: .milliseconds(20))
        #expect(window.firstResponder === previousResponder)
    }
}

private final class FocusProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
