import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("SwitchableSpeechProviders")
struct SwitchableSpeechProvidersTests {
    @Test
    func localWhisperProviderResolvesModelFromFilesystemOffMainActor() async throws {
        let suiteName = "SwitchableSpeechProvidersTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }

        let modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchableSpeechProvidersTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: modelsDirectory)
        }

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let modelURL = modelsDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        FileManager.default.createFile(atPath: modelURL.path, contents: Data("test".utf8))

        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.speechProvider = .localWhisper
        configuration.localWhisperModel = "ggml-large-v3-turbo-q5_0"
        defaults.set(try JSONEncoder().encode(configuration), forKey: "model.openaiConfiguration")

        let deepgramClient = MockTranscriptionClient()
        let whisperClient = MockTranscriptionClient()
        let localWhisperClient = MockTranscriptionClient()
        let localSenseVoiceClient = MockTranscriptionClient()
        let client = SwitchableSpeechTranscriptionClient(
            defaults: defaults,
            deepgramClient: deepgramClient,
            whisperClient: whisperClient,
            localWhisperClient: localWhisperClient,
            localSenseVoiceClient: localSenseVoiceClient,
            localWhisperModelsDirectory: modelsDirectory,
            defaultLocalWhisperModelName: "ggml-large-v3-turbo-q5_0",
            localSenseVoiceModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalSenseVoiceModelName: "sensevoice-small-int8"
        )

        try await Task.detached {
            try await client.connect(
                apiKey: "local-whisper-model",
                configuration: LiveTranscriptionConfiguration()
            )
        }.value

        #expect(localWhisperClient.connectCallCount == 1)
        #expect(localWhisperClient.lastConfiguration?.endpoint == modelURL)
        #expect(deepgramClient.connectCallCount == 0)
        #expect(whisperClient.connectCallCount == 0)
        #expect(localSenseVoiceClient.connectCallCount == 0)
    }

    @Test
    func localSenseVoiceProviderResolvesModelDirectoryFromFilesystemOffMainActor() async throws {
        let suiteName = "SwitchableSpeechProvidersTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }

        let modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchableSpeechProvidersSenseVoiceTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: modelsDirectory)
        }

        let modelDirectory = modelsDirectory.appendingPathComponent("sensevoice-small-int8", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("model.int8.onnx").path, contents: Data("test".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("tokens.txt").path, contents: Data("test".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent(".ready").path, contents: Data())

        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.speechProvider = .localSenseVoice
        configuration.localSenseVoiceModel = "sensevoice-small-int8"
        defaults.set(try JSONEncoder().encode(configuration), forKey: "model.openaiConfiguration")

        let deepgramClient = MockTranscriptionClient()
        let whisperClient = MockTranscriptionClient()
        let localWhisperClient = MockTranscriptionClient()
        let localSenseVoiceClient = MockTranscriptionClient()
        let client = SwitchableSpeechTranscriptionClient(
            defaults: defaults,
            deepgramClient: deepgramClient,
            whisperClient: whisperClient,
            localWhisperClient: localWhisperClient,
            localSenseVoiceClient: localSenseVoiceClient,
            localWhisperModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalWhisperModelName: "ggml-large-v3-turbo-q5_0",
            localSenseVoiceModelsDirectory: modelsDirectory,
            defaultLocalSenseVoiceModelName: "sensevoice-small-int8"
        )

        try await Task.detached {
            try await client.connect(
                apiKey: "local-sensevoice-model",
                configuration: LiveTranscriptionConfiguration()
            )
        }.value

        #expect(localSenseVoiceClient.connectCallCount == 1)
        #expect(localSenseVoiceClient.lastConfiguration?.endpoint == modelDirectory)
        #expect(deepgramClient.connectCallCount == 0)
        #expect(whisperClient.connectCallCount == 0)
        #expect(localWhisperClient.connectCallCount == 0)
    }

    @Test
    func whisper429FallsBackToDeepgramAndReplaysAudio() async throws {
        let suiteName = "SwitchableSpeechProvidersTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        defaults.set("deepgram-test-key", forKey: "credentials.com.slashvibe.desktop.deepgram-api-key")

        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.speechProvider = .whisper
        defaults.set(try JSONEncoder().encode(configuration), forKey: "model.openaiConfiguration")

        let deepgramClient = MockTranscriptionClient()
        let whisperClient = MockTranscriptionClient()
        whisperClient.finalizeError = OpenAIWhisperTranscriptionClientError.badHTTPStatus(429, "busy")
        let localWhisperClient = MockTranscriptionClient()
        let localSenseVoiceClient = MockTranscriptionClient()
        let client = SwitchableSpeechTranscriptionClient(
            defaults: defaults,
            deepgramClient: deepgramClient,
            whisperClient: whisperClient,
            localWhisperClient: localWhisperClient,
            localSenseVoiceClient: localSenseVoiceClient,
            localWhisperModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalWhisperModelName: "ggml-large-v3-turbo-q5_0",
            localSenseVoiceModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalSenseVoiceModelName: "sensevoice-small-int8"
        )

        let chunk = AudioChunk(
            data: Data([0x01, 0x02, 0x03, 0x04]),
            format: .deepgramLinear16,
            sequenceNumber: 1
        )

        try await client.connect(
            apiKey: "openai-test-key",
            configuration: LiveTranscriptionConfiguration()
        )
        try await client.send(audioChunk: chunk)
        try await client.finalize()

        #expect(whisperClient.connectCallCount == 1)
        #expect(whisperClient.finalizeCallCount == 1)
        #expect(deepgramClient.connectCallCount == 1)
        #expect(deepgramClient.finalizeCallCount == 1)
        #expect(deepgramClient.sentChunks == [chunk])
        #expect(localWhisperClient.connectCallCount == 0)
        #expect(localSenseVoiceClient.connectCallCount == 0)
    }

    @Test
    func localWhisperTimeoutFallsBackToDeepgramAndReplaysAudio() async throws {
        let suiteName = "SwitchableSpeechProvidersTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }

        let modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchableSpeechProvidersTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: modelsDirectory)
        }

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let modelURL = modelsDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        FileManager.default.createFile(atPath: modelURL.path, contents: Data("test".utf8))
        defaults.set("deepgram-test-key", forKey: "credentials.com.slashvibe.desktop.deepgram-api-key")

        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.speechProvider = .localWhisper
        configuration.localWhisperModel = "ggml-large-v3-turbo-q5_0"
        defaults.set(try JSONEncoder().encode(configuration), forKey: "model.openaiConfiguration")

        let deepgramClient = MockTranscriptionClient()
        let whisperClient = MockTranscriptionClient()
        let localWhisperClient = MockTranscriptionClient()
        localWhisperClient.finalizeDelay = .milliseconds(50)
        let localSenseVoiceClient = MockTranscriptionClient()
        let client = SwitchableSpeechTranscriptionClient(
            defaults: defaults,
            deepgramClient: deepgramClient,
            whisperClient: whisperClient,
            localWhisperClient: localWhisperClient,
            localSenseVoiceClient: localSenseVoiceClient,
            localWhisperModelsDirectory: modelsDirectory,
            defaultLocalWhisperModelName: "ggml-large-v3-turbo-q5_0",
            localSenseVoiceModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalSenseVoiceModelName: "sensevoice-small-int8",
            localWhisperFinalizeTimeout: .milliseconds(10)
        )

        let chunk = AudioChunk(
            data: Data([0x10, 0x20, 0x30, 0x40]),
            format: .deepgramLinear16,
            sequenceNumber: 1
        )

        try await client.connect(
            apiKey: "local-whisper-model",
            configuration: LiveTranscriptionConfiguration()
        )
        try await client.send(audioChunk: chunk)
        try await client.finalize()

        #expect(localWhisperClient.connectCallCount == 1)
        #expect(localWhisperClient.finalizeCallCount == 1)
        #expect(deepgramClient.connectCallCount == 1)
        #expect(deepgramClient.finalizeCallCount == 1)
        #expect(deepgramClient.sentChunks == [chunk])
        #expect(whisperClient.connectCallCount == 0)
        #expect(localSenseVoiceClient.connectCallCount == 0)
    }

    @Test
    func localWhisperEmptyTranscriptFallsBackToDeepgramAndReplaysAudio() async throws {
        let suiteName = "SwitchableSpeechProvidersTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }

        let modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchableSpeechProvidersTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: modelsDirectory)
        }

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let modelURL = modelsDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        FileManager.default.createFile(atPath: modelURL.path, contents: Data("test".utf8))
        defaults.set("deepgram-test-key", forKey: "credentials.com.slashvibe.desktop.deepgram-api-key")

        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.speechProvider = .localWhisper
        configuration.localWhisperModel = "ggml-large-v3-turbo-q5_0"
        defaults.set(try JSONEncoder().encode(configuration), forKey: "model.openaiConfiguration")

        let deepgramClient = MockTranscriptionClient()
        let whisperClient = MockTranscriptionClient()
        let localWhisperClient = MockTranscriptionClient()
        localWhisperClient.finalizeError = LocalWhisperTranscriptionClientError.emptyTranscript
        let localSenseVoiceClient = MockTranscriptionClient()
        let client = SwitchableSpeechTranscriptionClient(
            defaults: defaults,
            deepgramClient: deepgramClient,
            whisperClient: whisperClient,
            localWhisperClient: localWhisperClient,
            localSenseVoiceClient: localSenseVoiceClient,
            localWhisperModelsDirectory: modelsDirectory,
            defaultLocalWhisperModelName: "ggml-large-v3-turbo-q5_0",
            localSenseVoiceModelsDirectory: FileManager.default.temporaryDirectory,
            defaultLocalSenseVoiceModelName: "sensevoice-small-int8"
        )

        let chunk = AudioChunk(
            data: Data([0x10, 0x20, 0x30, 0x40]),
            format: .deepgramLinear16,
            sequenceNumber: 1
        )

        try await client.connect(
            apiKey: "local-whisper-model",
            configuration: LiveTranscriptionConfiguration()
        )
        try await client.send(audioChunk: chunk)
        try await client.finalize()

        #expect(localWhisperClient.connectCallCount == 1)
        #expect(localWhisperClient.finalizeCallCount == 1)
        #expect(deepgramClient.connectCallCount == 1)
        #expect(deepgramClient.finalizeCallCount == 1)
        #expect(deepgramClient.sentChunks == [chunk])
        #expect(whisperClient.connectCallCount == 0)
        #expect(localSenseVoiceClient.connectCallCount == 0)
    }
}
