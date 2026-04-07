import Testing
@testable import SpeechBarInfrastructure

@Suite("LocalWhisperTranscriptNormalization")
struct LocalWhisperTranscriptNormalizationTests {
    @Test
    func collapsesExactRepeatedSentence() {
        let transcript = "现在还是会出现粘贴很多次的情况 现在还是会出现粘贴很多次的情况 现在还是会出现粘贴很多次的情况"

        let normalized = LocalWhisperTranscriptionClient.normalizeTranscriptForInput(transcript)

        #expect(normalized == "现在还是会出现粘贴很多次的情况")
    }

    @Test
    func collapsesRepeatedSentenceWithMissingLeadingCharacter() {
        let transcript = "你说的这种发布的固定等待时间是什么东西? 说的这种发布的固定等待时间是什么东西? 说的这种发布的固定等待时间是什么东西?"

        let normalized = LocalWhisperTranscriptionClient.normalizeTranscriptForInput(transcript)

        #expect(normalized == "你说的这种发布的固定等待时间是什么东西")
    }
}
