@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import SpeechBarDomain

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [Mic] \(message)\n"
    let path = "/tmp/speechbar_debug.log"
    if let data = line.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

public final class MacBuiltInMicSource: NSObject, AudioInputSource, @unchecked Sendable {
    public let audioLevels: AsyncStream<AudioLevelSample>

    private let engine = AVAudioEngine()
    private let preferredDeviceUIDProvider: @Sendable () -> String?
    private let audioProcessingQueue = DispatchQueue(
        label: "com.startup.speechbar.audio-processing",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private let targetFormat: AVAudioFormat
    private let audioLevelsContinuation: AsyncStream<AudioLevelSample>.Continuation
    private let preRollBytesTarget = 8_000
    private let tailGraceDuration: Duration = .milliseconds(120)

    private var converter: AVAudioConverter?
    private var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation?
    private var sequenceNumber: Int64 = 0
    private var pendingPreRollChunks: [AudioChunk] = []
    private var pendingPreRollByteCount = 0
    private var hasFlushedPreRoll = false

    public init(
        preferredDeviceUIDProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.preferredDeviceUIDProvider = preferredDeviceUIDProvider
        var capturedAudioLevelsContinuation: AsyncStream<AudioLevelSample>.Continuation?
        self.audioLevels = AsyncStream { continuation in
            capturedAudioLevelsContinuation = continuation
        }
        self.audioLevelsContinuation = capturedAudioLevelsContinuation!
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        super.init()
    }

    public func requestRecordPermission() async -> AudioInputPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        @unknown default:
            return .denied
        }
    }

    public func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        await stopCapture()

        let stream = AsyncThrowingStream<AudioChunk, Error> { continuation in
            self.storeContinuation(continuation)

            continuation.onTermination = { _ in
                Task {
                    await self.stopCapture()
                }
            }
        }

        do {
            try configureAudioEngine()
        } catch {
            finishContinuation()
            throw error
        }

        return stream
    }

    public func stopCapture() async {
        let shouldWaitForTail: Bool = {
            stateLock.lock()
            let shouldWait = continuation != nil
            stateLock.unlock()
            return shouldWait
        }()

        if shouldWaitForTail {
            try? await Task.sleep(for: tailGraceDuration)
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        // Drain any buffers already copied off the realtime audio thread before
        // clearing converter/continuation, otherwise short utterances get dropped.
        audioProcessingQueue.sync {}

        clearConverter()

        finishContinuation()
    }

    private func configureAudioEngine() throws {
        let inputNode = engine.inputNode
        applyPreferredInputDeviceIfPossible(to: inputNode)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        setConverter(AVAudioConverter(from: inputFormat, to: targetFormat))

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat,
            block: makeAudioTapBlock(
                owner: self,
                sourceFormat: inputFormat,
                processingQueue: audioProcessingQueue
            )
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            clearConverter()
            throw error
        }
    }

    private func applyPreferredInputDeviceIfPossible(to inputNode: AVAudioInputNode) {
        guard
            let preferredDeviceUID = preferredDeviceUIDProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !preferredDeviceUID.isEmpty,
            let preferredDeviceID = AudioInputDeviceCatalog.deviceID(forUID: preferredDeviceUID),
            let audioUnit = inputNode.audioUnit
        else {
            return
        }

        var deviceID = preferredDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            debugLog("failed to switch preferred input device, status=\(status), uid=\(preferredDeviceUID)")
        } else {
            debugLog("using preferred input device uid=\(preferredDeviceUID)")
        }
    }

    fileprivate func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) {
        guard let converter = currentConverter() else { return }

        // Log input buffer info once
        if sequenceNumber == 0 {
            let hasFloat = buffer.floatChannelData != nil
            let hasInt16 = buffer.int16ChannelData != nil
            debugLog("input format: \(sourceFormat), frames=\(buffer.frameLength), hasFloat=\(hasFloat), hasInt16=\(hasInt16)")
            debugLog("target format: \(targetFormat)")

            // Check if input has actual audio data
            if let floatData = buffer.floatChannelData {
                let samples = UnsafeBufferPointer(start: floatData[0], count: min(Int(buffer.frameLength), 100))
                let maxSample = samples.max() ?? 0
                let minSample = samples.min() ?? 0
                debugLog("input float sample range: \(minSample) to \(maxSample)")
            }
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 8)
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(frameCapacity, 256)
        ) else {
            return
        }

        let inputState = ConverterInputState()
        var conversionError: NSError?

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if inputState.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputState.didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            debugLog("conversion error: \(conversionError?.localizedDescription ?? "unknown")")
            stateLock.lock()
            continuation?.yield(with: .failure(conversionError ?? NSError(domain: "MacBuiltInMicSource", code: -1)))
            continuation = nil
            stateLock.unlock()
            return
        }

        guard convertedBuffer.frameLength > 0 else {
            debugLog("converted buffer has 0 frames, status=\(status.rawValue)")
            return
        }
        guard let channelData = convertedBuffer.int16ChannelData else {
            debugLog("no int16ChannelData in converted buffer")
            return
        }

        let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        let audioLevelSample = makeAudioLevelSample(
            samples: channelData[0],
            count: Int(convertedBuffer.frameLength)
        )
        audioLevelsContinuation.yield(audioLevelSample)

        // Log converted data info once
        if sequenceNumber == 0 {
            let samples = UnsafeBufferPointer(start: channelData[0], count: min(Int(convertedBuffer.frameLength), 100))
            let maxSample = samples.max() ?? 0
            let minSample = samples.min() ?? 0
            let nonZero = data.filter { $0 != 0 }.count
            debugLog("converted: frames=\(convertedBuffer.frameLength), bytes=\(byteCount), nonZero=\(nonZero), int16 range: \(minSample) to \(maxSample)")
        }

        stateLock.lock()
        let currentSequence = sequenceNumber
        sequenceNumber += 1
        let chunk = AudioChunk(
            data: data,
            format: .deepgramLinear16,
            sequenceNumber: currentSequence
        )
        if hasFlushedPreRoll {
            continuation?.yield(chunk)
        } else {
            pendingPreRollChunks.append(chunk)
            pendingPreRollByteCount += data.count
            if pendingPreRollByteCount >= preRollBytesTarget {
                flushPendingPreRollLocked()
            }
        }
        stateLock.unlock()
    }

    private func storeContinuation(_ continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation) {
        stateLock.lock()
        self.continuation = continuation
        self.sequenceNumber = 0
        self.pendingPreRollChunks = []
        self.pendingPreRollByteCount = 0
        self.hasFlushedPreRoll = false
        stateLock.unlock()
    }

    private func finishContinuation() {
        stateLock.lock()
        flushPendingPreRollLocked()
        continuation?.finish()
        continuation = nil
        pendingPreRollChunks = []
        pendingPreRollByteCount = 0
        hasFlushedPreRoll = false
        stateLock.unlock()
    }

    private func setConverter(_ converter: AVAudioConverter?) {
        stateLock.lock()
        self.converter = converter
        stateLock.unlock()
    }

    private func clearConverter() {
        setConverter(nil)
    }

    private func currentConverter() -> AVAudioConverter? {
        stateLock.lock()
        let converter = self.converter
        stateLock.unlock()
        return converter
    }

    private func flushPendingPreRollLocked() {
        guard !hasFlushedPreRoll else { return }
        hasFlushedPreRoll = true
        for chunk in pendingPreRollChunks {
            continuation?.yield(chunk)
        }
        pendingPreRollChunks.removeAll(keepingCapacity: false)
        pendingPreRollByteCount = 0
    }

    private func makeAudioLevelSample(
        samples: UnsafeMutablePointer<Int16>,
        count: Int
    ) -> AudioLevelSample {
        guard count > 0 else {
            return AudioLevelSample(level: 0, peak: 0)
        }

        let buffer = UnsafeBufferPointer(start: samples, count: count)
        var squareSum = 0.0
        var peak = 0.0

        for sample in buffer {
            let normalized = abs(Double(sample)) / Double(Int16.max)
            squareSum += normalized * normalized
            peak = max(peak, normalized)
        }

        let rms = sqrt(squareSum / Double(count))
        let uiLevel = min(1.0, max(0.0, rms * 10.0))
        return AudioLevelSample(level: uiLevel, peak: min(1.0, peak))
    }
}

private func makeAudioTapBlock(
    owner: MacBuiltInMicSource,
    sourceFormat: AVAudioFormat,
    processingQueue: DispatchQueue
) -> AVAudioNodeTapBlock {
    { [weak owner] buffer, _ in
        guard let owner, let copiedBuffer = copyPCMBuffer(buffer) else {
            return
        }

        processingQueue.async { [weak owner] in
            owner?.handleIncomingBuffer(copiedBuffer, sourceFormat: sourceFormat)
        }
    }
}

private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copiedBuffer = AVAudioPCMBuffer(
        pcmFormat: buffer.format,
        frameCapacity: buffer.frameLength
    ) else {
        return nil
    }

    copiedBuffer.frameLength = buffer.frameLength

    let frames = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)

    switch buffer.format.commonFormat {
    case .pcmFormatFloat32:
        guard let source = buffer.floatChannelData,
              let destination = copiedBuffer.floatChannelData else {
            return nil
        }
        let sampleCount = buffer.format.isInterleaved ? frames * channelCount : frames
        let byteCount = sampleCount * MemoryLayout<Float>.size
        if buffer.format.isInterleaved {
            memcpy(destination[0], source[0], byteCount)
        } else {
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        }

    case .pcmFormatInt16:
        guard let source = buffer.int16ChannelData,
              let destination = copiedBuffer.int16ChannelData else {
            return nil
        }
        let sampleCount = buffer.format.isInterleaved ? frames * channelCount : frames
        let byteCount = sampleCount * MemoryLayout<Int16>.size
        if buffer.format.isInterleaved {
            memcpy(destination[0], source[0], byteCount)
        } else {
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        }

    case .pcmFormatInt32:
        guard let source = buffer.int32ChannelData,
              let destination = copiedBuffer.int32ChannelData else {
            return nil
        }
        let sampleCount = buffer.format.isInterleaved ? frames * channelCount : frames
        let byteCount = sampleCount * MemoryLayout<Int32>.size
        if buffer.format.isInterleaved {
            memcpy(destination[0], source[0], byteCount)
        } else {
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        }

    case .pcmFormatFloat64:
        guard let source = buffer.floatChannelData,
              let destination = copiedBuffer.floatChannelData else {
            return nil
        }
        let sampleCount = buffer.format.isInterleaved ? frames * channelCount : frames
        let byteCount = sampleCount * MemoryLayout<Float>.size
        if buffer.format.isInterleaved {
            memcpy(destination[0], source[0], byteCount)
        } else {
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        }

    default:
        return nil
    }

    return copiedBuffer
}

private final class ConverterInputState: @unchecked Sendable {
    var didProvideInput = false
}
