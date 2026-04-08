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
}
