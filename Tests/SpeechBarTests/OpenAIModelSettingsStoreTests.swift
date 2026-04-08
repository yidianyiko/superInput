import Foundation
import Testing
@testable import SpeechBarApp
import SpeechBarInfrastructure

@Suite("OpenAIModelSettingsStore")
struct OpenAIModelSettingsStoreTests {
    @Test
    func normalizingSharedEndpointAppendsResponsesPathForOpenAIBaseURL() {
        var configuration = OpenAIModelSettingsStore.StoredConfiguration()
        configuration.researchEndpoint = "https://api.openai.com/v1"

        let normalized = OpenAIModelSettingsStore.StoredConfiguration.normalized(configuration)

        #expect(normalized.researchEndpoint == "https://api.openai.com/v1/responses")
        #expect(normalized.polishEndpoint == "https://api.openai.com/v1/responses")
        #expect(normalized.openAISpeechEndpoint == "https://api.openai.com/v1/audio/transcriptions")
    }

    @Test
    func storedConfigurationLoadsLegacyPayloadsWithoutResettingProvider() throws {
        let suiteName = "OpenAIModelSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyPayload = """
        {
          "researchModel":"gpt-4.1-mini",
          "deepgramSpeechLanguage":"zh-CN",
          "deepgramSpeechEndpoint":"https://api.deepgram.com/v1/listen",
          "polishEndpoint":"https://api.vectorengine.ai/v1/responses",
          "openAISpeechEndpoint":"https://api.vectorengine.ai/v1/audio/transcriptions",
          "deepgramSpeechModel":"nova-2",
          "openAISpeechModel":"whisper-1",
          "polishModel":"gpt-4.1-mini",
          "researchEndpoint":"https://api.vectorengine.ai/v1/responses",
          "openAISpeechLanguage":"zh",
          "speechProvider":"whisper"
        }
        """
        defaults.set(Data(legacyPayload.utf8), forKey: "model.openaiConfiguration")

        let configuration = OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults)

        #expect(configuration.speechProvider == .whisper)
        #expect(configuration.openAISpeechModel == "whisper-1")
        #expect(configuration.localWhisperModel == OpenAIModelSettingsStore.StoredConfiguration.defaultLocalWhisperModel)
        #expect(configuration.localSenseVoiceModel == OpenAIModelSettingsStore.StoredConfiguration.defaultLocalSenseVoiceModel)
        #expect(
            configuration.localWhisperLanguage
                == OpenAIModelSettingsStore.StoredConfiguration.defaultLocalWhisperLanguage
        )
        #expect(
            configuration.localSenseVoiceLanguage
                == OpenAIModelSettingsStore.StoredConfiguration.defaultLocalSenseVoiceLanguage
        )
    }

    @Test
    @MainActor
    func switchingSpeechProviderPersistsNormalizedConfigurationWithoutRecursing() throws {
        let suiteName = "OpenAIModelSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite.")
            return
        }
        let modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAIModelSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        let senseVoiceModelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAIModelSettingsStoreTests-SenseVoice-\(UUID().uuidString)", isDirectory: true)
        let senseVoiceRuntimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAIModelSettingsStoreTests-RT-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: modelsDirectory)
            try? FileManager.default.removeItem(at: senseVoiceModelsDirectory)
            try? FileManager.default.removeItem(at: senseVoiceRuntimeDirectory)
        }

        let localWhisperModelStore = LocalWhisperModelStore(
            defaults: defaults,
            modelsDirectory: modelsDirectory
        )
        let senseVoiceModelStore = SenseVoiceModelStore(
            defaults: defaults,
            modelsDirectory: senseVoiceModelsDirectory,
            runtimeDirectory: senseVoiceRuntimeDirectory
        )
        let store = OpenAIModelSettingsStore(
            defaults: defaults,
            deepgramCredentialProvider: MockCredentialProvider(storedAPIKey: "deepgram-test-key"),
            openAICredentialProvider: MockCredentialProvider(storedAPIKey: "openai-test-key"),
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore
        )

        store.configuration.researchEndpoint = "https://example.com/v1/responses"
        store.configuration.speechProvider = .deepgram

        let savedConfiguration = OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults)

        #expect(savedConfiguration.speechProvider == .deepgram)
        #expect(savedConfiguration.researchEndpoint == "https://example.com/v1/responses")
        #expect(savedConfiguration.openAISpeechEndpoint == "https://example.com/v1/audio/transcriptions")
    }
}
