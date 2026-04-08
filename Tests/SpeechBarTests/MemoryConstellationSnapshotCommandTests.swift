import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationSnapshotCommand")
struct MemoryConstellationSnapshotCommandTests {
    @Test
    func parsesMemoryScenarioAndDisplayModeOverrides() throws {
        let command = try #require(OffscreenHomeSnapshotCommand.parse(arguments: [
            "speechbar",
            "--render-home-snapshot",
            "--memory-scenario", "privacy",
            "--memory-display-mode", "privacySafe"
        ]))

        #expect(command.memoryScenario == .privacy)
        #expect(command.memoryDisplayMode == .privacySafe)
    }

    @Test
    func parsesVoltThemeOverrideAndMapsToGreenPreset() throws {
        let command = try #require(OffscreenHomeSnapshotCommand.parse(arguments: [
            "speechbar",
            "--render-home-snapshot",
            "--theme", "volt"
        ]))

        #expect(command.theme == .volt)
        #expect(OffscreenHomeSnapshotCommand.ThemeOverride.volt.themePreset == .green)
    }

    @Test
    func preloadHelperWaitsForReloadClosureToFinish() async throws {
        let gate = AsyncGate()
        let probe = ReturnProbe()

        let task = Task {
            await OffscreenHomeSnapshotRenderer.preloadMemoryConstellation(reload: {
                await gate.wait()
            })
            await probe.markReturned()
        }

        await Task.yield()
        #expect(await probe.hasReturned() == false)

        await gate.open()
        await task.value

        #expect(await probe.hasReturned() == true)
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ReturnProbe {
    private var returned = false

    func markReturned() {
        returned = true
    }

    func hasReturned() -> Bool {
        returned
    }
}
