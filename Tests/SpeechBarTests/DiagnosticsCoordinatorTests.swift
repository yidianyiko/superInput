import Foundation
import Testing
@testable import SpeechBarApplication
import SpeechBarDomain

@Suite("DiagnosticsCoordinator")
struct DiagnosticsCoordinatorTests {
    @Test
    @MainActor
    func capturesReplayBundleAfterWritingArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = DiagnosticsCoordinator(baseDirectory: root)
        coordinator.recordObservation(
            AgentObservationEvent(
                provider: .codexCLI,
                sessionID: "codex:1",
                kind: .taskStarted,
                title: "Test task",
                message: "hello"
            )
        )
        coordinator.recordSnapshots(
            runtimeSnapshots: [],
            taskBoardSnapshot: nil,
            embeddedDisplaySnapshot: nil
        )
        coordinator.recordDiagnostic(
            subsystem: "test",
            severity: .warning,
            message: "bundle me"
        )

        try await Task.sleep(for: .milliseconds(200))
        coordinator.captureReplayBundle(reason: "unit-test", provider: .codexCLI)

        #expect(coordinator.recentBundles.count == 1)
        let bundle = try #require(coordinator.recentBundles.first)
        #expect(FileManager.default.fileExists(atPath: bundle.rawEventsFile.path))
        #expect(FileManager.default.fileExists(atPath: bundle.snapshotsFile.path))
        #expect(FileManager.default.fileExists(atPath: bundle.diagnosticsFile.path))
    }
}
