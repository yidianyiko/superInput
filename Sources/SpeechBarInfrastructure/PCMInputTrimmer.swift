import Foundation

struct TrimmedPCMInput: Sendable {
    let data: Data
    let leadingSamplesTrimmed: Int
    let trailingSamplesTrimmed: Int
}

enum PCMInputTrimmer {
    static func trimMonoInt16PCM(
        _ data: Data,
        sampleRate: Int,
        amplitudeThreshold: Int16 = 160,
        leadingPaddingMilliseconds: Int = 80,
        trailingPaddingMilliseconds: Int = 140,
        blockMilliseconds: Int = 10
    ) -> TrimmedPCMInput {
        guard data.count >= MemoryLayout<Int16>.size else {
            return TrimmedPCMInput(data: data, leadingSamplesTrimmed: 0, trailingSamplesTrimmed: 0)
        }

        let samples = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Int16.self))
        }
        guard !samples.isEmpty else {
            return TrimmedPCMInput(data: data, leadingSamplesTrimmed: 0, trailingSamplesTrimmed: 0)
        }

        let blockSize = max(1, sampleRate * blockMilliseconds / 1_000)
        var firstSpeechSample: Int?
        var lastSpeechSample: Int?

        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + blockSize)
            let block = samples[index..<end]
            let peak = block.reduce(0) { current, sample in
                max(current, Int(abs(Int(sample))))
            }

            if peak >= Int(amplitudeThreshold) {
                firstSpeechSample = firstSpeechSample ?? index
                lastSpeechSample = end
            }

            index = end
        }

        guard let firstSpeechSample, let lastSpeechSample else {
            return TrimmedPCMInput(data: data, leadingSamplesTrimmed: 0, trailingSamplesTrimmed: 0)
        }

        let leadingPaddingSamples = sampleRate * leadingPaddingMilliseconds / 1_000
        let trailingPaddingSamples = sampleRate * trailingPaddingMilliseconds / 1_000

        let trimmedStart = max(0, firstSpeechSample - leadingPaddingSamples)
        let trimmedEnd = min(samples.count, lastSpeechSample + trailingPaddingSamples)

        guard trimmedStart > 0 || trimmedEnd < samples.count else {
            return TrimmedPCMInput(data: data, leadingSamplesTrimmed: 0, trailingSamplesTrimmed: 0)
        }

        let trimmedSamples = Array(samples[trimmedStart..<trimmedEnd])
        let trimmedData = trimmedSamples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        return TrimmedPCMInput(
            data: trimmedData,
            leadingSamplesTrimmed: trimmedStart,
            trailingSamplesTrimmed: samples.count - trimmedEnd
        )
    }
}
