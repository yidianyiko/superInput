import Foundation
import Testing
import SpeechBarDomain
@testable import SpeechBarInfrastructure

@Suite("EmbeddedDisplaySupport")
struct EmbeddedDisplaySupportTests {
    @Test
    func utf8TruncationDoesNotSplitChineseCharacters() {
        let text = "你好世界abc"
        let truncated = UTF8SafeTruncator.truncated(text, maxByteCount: 5)
        #expect(truncated == "你")
    }

    @Test
    func encoderSplitsFramesAndProducesStableDigest() throws {
        let encoder = EmbeddedDisplayEncoder()
        let snapshot = EmbeddedDisplaySnapshot(
            sequence: 42,
            mode: .multiTaskBoard,
            taskBoard: TaskBoardSnapshot(
                cards: [
                    TaskCardSnapshot(
                        id: "codex:1",
                        provider: .codexCLI,
                        title: String(repeating: "A", count: 40),
                        boardState: .run,
                        progressText: String(repeating: "B", count: 80),
                        elapsedSeconds: 12,
                        isSelected: true
                    )
                ],
                hiddenCount: 0,
                selectedCardID: "codex:1",
                isGlobalBrowseMode: false,
                layoutMode: .stretched,
                providerSummaries: [
                    ProviderSummarySnapshot(provider: .codexCLI, activeTaskCount: 1)
                ]
            ),
            waveform: AudioWaveformSnapshot(levelBars: Array(repeating: 50, count: 16), peak: 90, recordingState: "recording", subtitle: "Listening")
        )

        let digestA = try encoder.digest(for: snapshot)
        let digestB = try encoder.digest(for: snapshot)
        let frames = try encoder.makeFrames(for: snapshot, mtu: 48)

        #expect(digestA == digestB)
        #expect(frames.count > 1)
        #expect(frames.allSatisfy { $0.sequence == 42 })
    }
}
