import Foundation
import Testing
@testable import SpeechBarInfrastructure

@Suite("PCMInputTrimmer")
struct PCMInputTrimmerTests {
    @Test
    func minimumLeadingRetainedMillisecondsCapsStartTrim() {
        let sampleRate = 16_000
        let leadingSilenceSamples = sampleRate * 9 / 10
        let speechSamples = sampleRate / 10
        let samples = Array(repeating: Int16(0), count: leadingSilenceSamples)
            + Array(repeating: Int16(1_500), count: speechSamples)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let trimmed = PCMInputTrimmer.trimMonoInt16PCM(
            data,
            sampleRate: sampleRate,
            amplitudeThreshold: 80,
            leadingPaddingMilliseconds: 100,
            trailingPaddingMilliseconds: 0,
            minimumLeadingRetainedMilliseconds: 600
        )

        #expect(trimmed.leadingSamplesTrimmed == sampleRate * 6 / 10)
        #expect(trimmed.trailingSamplesTrimmed == 0)
    }

    @Test
    func prependLeadingSilenceAddsContextWithoutSpeechTrim() {
        let sampleRate = 16_000
        let speechSamples = sampleRate / 5
        let samples = Array(repeating: Int16(1_200), count: speechSamples)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        let trimmed = PCMInputTrimmer.trimMonoInt16PCM(
            data,
            sampleRate: sampleRate,
            amplitudeThreshold: 80,
            leadingPaddingMilliseconds: 0,
            trailingPaddingMilliseconds: 0,
            minimumLeadingRetainedMilliseconds: 0,
            prependLeadingSilenceMilliseconds: 120
        )

        let outputSamples = trimmed.data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Int16.self))
        }
        let prependedSamples = sampleRate * 120 / 1_000

        #expect(outputSamples.count == speechSamples + prependedSamples)
        #expect(outputSamples.prefix(prependedSamples).allSatisfy { $0 == 0 })
        #expect(outputSamples.suffix(speechSamples).allSatisfy { $0 == 1_200 })
    }
}
