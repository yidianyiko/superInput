import Combine
import Foundation
import SpeechBarDomain
import SpeechBarInfrastructure

enum SpeechTranscriptionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case deepgram
    case whisper
    case localWhisper
    case localSenseVoice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepgram:
            "Deepgram"
        case .whisper:
            "Whisper API"
        case .localWhisper:
            "本地 Whisper"
        case .localSenseVoice:
            "本地 SenseVoice"
        }
    }

    var credentialLabel: String {
        switch self {
        case .deepgram:
            "Deepgram Key"
        case .whisper:
            "OpenAI Key"
        case .localWhisper:
            "本地模型"
        case .localSenseVoice:
            "SenseVoice"
        }
    }
}

@MainActor
final class OpenAIModelSettingsStore: ObservableObject, OpenAIResponsesConfigurationProviding, @unchecked Sendable {
    struct StoredConfiguration: Codable, Equatable {
        static let defaultResponsesEndpoint = "https://api.vectorengine.ai/v1/responses"
        static let defaultTranscriptionsEndpoint = "https://api.vectorengine.ai/v1/audio/transcriptions"
        static let defaultLocalWhisperModel = LocalWhisperModelDescriptor.ggmlLargeV3TurboQ50.name
        static let defaultLocalWhisperLanguage = LocalWhisperModelDescriptor.ggmlLargeV3TurboQ50.defaultLanguage
        static let defaultLocalSenseVoiceModel = SenseVoiceModelDescriptor.smallInt8.name
        static let defaultLocalSenseVoiceLanguage = SenseVoiceModelDescriptor.smallInt8.defaultLanguage

        var speechProvider: SpeechTranscriptionProvider = .localWhisper
        var deepgramSpeechModel: String = "nova-2"
        var deepgramSpeechLanguage: String = "zh-CN"
        var deepgramSpeechEndpoint: String = "https://api.deepgram.com/v1/listen"
        var openAISpeechModel: String = "whisper-1"
        var openAISpeechLanguage: String = "zh"
        var openAISpeechEndpoint: String = defaultTranscriptionsEndpoint
        var localWhisperModel: String = defaultLocalWhisperModel
        var localWhisperLanguage: String = defaultLocalWhisperLanguage
        var localSenseVoiceModel: String = defaultLocalSenseVoiceModel
        var localSenseVoiceLanguage: String = defaultLocalSenseVoiceLanguage
        var researchModel: String = "gpt-4.1-mini"
        var polishModel: String = "gpt-4.1-mini"
        var researchEndpoint: String = defaultResponsesEndpoint
        var polishEndpoint: String = defaultResponsesEndpoint

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init()
            speechProvider = try container.decodeIfPresent(
                SpeechTranscriptionProvider.self,
                forKey: .speechProvider
            ) ?? speechProvider
            deepgramSpeechModel = try container.decodeIfPresent(String.self, forKey: .deepgramSpeechModel)
                ?? deepgramSpeechModel
            deepgramSpeechLanguage = try container.decodeIfPresent(String.self, forKey: .deepgramSpeechLanguage)
                ?? deepgramSpeechLanguage
            deepgramSpeechEndpoint = try container.decodeIfPresent(String.self, forKey: .deepgramSpeechEndpoint)
                ?? deepgramSpeechEndpoint
            openAISpeechModel = try container.decodeIfPresent(String.self, forKey: .openAISpeechModel)
                ?? openAISpeechModel
            openAISpeechLanguage = try container.decodeIfPresent(String.self, forKey: .openAISpeechLanguage)
                ?? openAISpeechLanguage
            openAISpeechEndpoint = try container.decodeIfPresent(String.self, forKey: .openAISpeechEndpoint)
                ?? openAISpeechEndpoint
            localWhisperModel = try container.decodeIfPresent(String.self, forKey: .localWhisperModel)
                ?? localWhisperModel
            localWhisperLanguage = try container.decodeIfPresent(String.self, forKey: .localWhisperLanguage)
                ?? localWhisperLanguage
            localSenseVoiceModel = try container.decodeIfPresent(String.self, forKey: .localSenseVoiceModel)
                ?? localSenseVoiceModel
            localSenseVoiceLanguage = try container.decodeIfPresent(String.self, forKey: .localSenseVoiceLanguage)
                ?? localSenseVoiceLanguage
            researchModel = try container.decodeIfPresent(String.self, forKey: .researchModel)
                ?? researchModel
            polishModel = try container.decodeIfPresent(String.self, forKey: .polishModel)
                ?? polishModel
            researchEndpoint = try container.decodeIfPresent(String.self, forKey: .researchEndpoint)
                ?? researchEndpoint
            polishEndpoint = try container.decodeIfPresent(String.self, forKey: .polishEndpoint)
                ?? polishEndpoint
        }

        static func load(from defaults: UserDefaults) -> Self {
            guard
                let data = defaults.data(forKey: Keys.configuration),
                let configuration = try? JSONDecoder().decode(Self.self, from: data)
            else {
                return normalized(Self())
            }
            return normalized(configuration)
        }

        static func normalized(_ configuration: Self) -> Self {
            var result = configuration

            let trimmedResearch = result.researchEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let researchEndpoint = responsesEndpoint(fromSharedEndpoint: trimmedResearch)?.absoluteString
                ?? defaultResponsesEndpoint
            result.researchEndpoint = researchEndpoint

            // Keep research/polish on the same API endpoint.
            result.polishEndpoint = researchEndpoint

            if let whisperURL = whisperEndpoint(fromResponsesEndpoint: researchEndpoint) {
                result.openAISpeechEndpoint = whisperURL.absoluteString
            } else {
                result.openAISpeechEndpoint = defaultTranscriptionsEndpoint
            }

            let trimmedSpeechModel = result.openAISpeechModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSpeechModel.isEmpty {
                result.openAISpeechModel = "whisper-1"
            }

            let trimmedSpeechLanguage = result.openAISpeechLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSpeechLanguage.isEmpty {
                result.openAISpeechLanguage = "zh"
            }

            let trimmedLocalModel = result.localWhisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLocalModel.isEmpty {
                result.localWhisperModel = defaultLocalWhisperModel
            }

            let trimmedLocalLanguage = result.localWhisperLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLocalLanguage.isEmpty {
                result.localWhisperLanguage = defaultLocalWhisperLanguage
            }

            let trimmedSenseVoiceModel = result.localSenseVoiceModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSenseVoiceModel.isEmpty {
                result.localSenseVoiceModel = defaultLocalSenseVoiceModel
            }

            let trimmedSenseVoiceLanguage = result.localSenseVoiceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSenseVoiceLanguage.isEmpty {
                result.localSenseVoiceLanguage = defaultLocalSenseVoiceLanguage
            }

            return result
        }

        static func responsesEndpoint(fromSharedEndpoint endpoint: String) -> URL? {
            guard var components = URLComponents(string: endpoint) else { return nil }

            let rawPath = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath =
                if rawPath == "/" {
                    ""
                } else if rawPath.hasSuffix("/") {
                    String(rawPath.dropLast())
                } else {
                    rawPath
                }

            if normalizedPath.hasSuffix("/responses") {
                components.path = normalizedPath
                return components.url
            }

            if normalizedPath.hasSuffix("/audio/transcriptions") {
                components.path = String(normalizedPath.dropLast("/audio/transcriptions".count)) + "/responses"
                return components.url
            }

            if normalizedPath.hasSuffix("/v1") {
                components.path = normalizedPath + "/responses"
                return components.url
            }

            if normalizedPath.isEmpty {
                components.path = "/v1/responses"
                return components.url
            }

            components.path = normalizedPath + "/responses"
            return components.url
        }

        static func whisperEndpoint(fromResponsesEndpoint endpoint: String) -> URL? {
            guard var components = URLComponents(string: endpoint) else { return nil }

            let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasSuffix("/audio/transcriptions") {
                return components.url
            }

            if path.hasSuffix("/responses") {
                components.path = String(path.dropLast("/responses".count)) + "/audio/transcriptions"
                return components.url
            }

            if path.hasSuffix("/v1") {
                components.path = path + "/audio/transcriptions"
                return components.url
            }

            if path.isEmpty || path == "/" {
                components.path = "/v1/audio/transcriptions"
                return components.url
            }

            components.path = path + "/audio/transcriptions"
            return components.url
        }
    }

    @Published var configuration: StoredConfiguration
    @Published var deepgramAPIKeyInput = ""
    @Published var openAIAPIKeyInput = ""
    @Published private(set) var deepgramCredentialStatus: CredentialStatus
    @Published private(set) var openAICredentialStatus: CredentialStatus
    @Published private(set) var localWhisperCredentialStatus: CredentialStatus
    @Published private(set) var localSenseVoiceCredentialStatus: CredentialStatus

    private let defaults: UserDefaults
    private let deepgramCredentialProvider: any CredentialProvider
    private let openAICredentialProvider: any CredentialProvider
    private let localWhisperModelStore: LocalWhisperModelStore
    private let senseVoiceModelStore: SenseVoiceModelStore
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingNormalizedConfiguration = false
    let isFreshInstall: Bool

    init(
        defaults: UserDefaults = .standard,
        deepgramCredentialProvider: any CredentialProvider,
        openAICredentialProvider: any CredentialProvider,
        localWhisperModelStore: LocalWhisperModelStore,
        senseVoiceModelStore: SenseVoiceModelStore
    ) {
        self.defaults = defaults
        self.deepgramCredentialProvider = deepgramCredentialProvider
        self.openAICredentialProvider = openAICredentialProvider
        self.localWhisperModelStore = localWhisperModelStore
        self.senseVoiceModelStore = senseVoiceModelStore
        self.isFreshInstall = defaults.data(forKey: Keys.configuration) == nil
        let storedConfiguration = StoredConfiguration.load(from: defaults)
        self.configuration = storedConfiguration
        self.deepgramCredentialStatus = deepgramCredentialProvider.credentialStatus()
        self.openAICredentialStatus = openAICredentialProvider.credentialStatus()
        self.localWhisperCredentialStatus = localWhisperModelStore.resolvedModelURL(
            preferredModelName: storedConfiguration.localWhisperModel
        ) == nil ? .missing : .available
        self.localSenseVoiceCredentialStatus = senseVoiceModelStore.resolvedModelDirectory(
            preferredModelName: storedConfiguration.localSenseVoiceModel
        ) == nil || !senseVoiceModelStore.isRuntimeInstalled ? .missing : .available
        bindPersistence()
    }

    var selectedSpeechProvider: SpeechTranscriptionProvider {
        configuration.speechProvider
    }

    var selectedSpeechProviderName: String {
        selectedSpeechProvider.displayName
    }

    var currentSpeechModel: String {
        switch selectedSpeechProvider {
        case .deepgram:
            configuration.deepgramSpeechModel
        case .whisper:
            configuration.openAISpeechModel
        case .localWhisper:
            configuration.localWhisperModel
        case .localSenseVoice:
            configuration.localSenseVoiceModel
        }
    }

    var currentSpeechLanguage: String {
        switch selectedSpeechProvider {
        case .deepgram:
            configuration.deepgramSpeechLanguage
        case .whisper:
            configuration.openAISpeechLanguage
        case .localWhisper:
            configuration.localWhisperLanguage
        case .localSenseVoice:
            configuration.localSenseVoiceLanguage
        }
    }

    var currentSpeechEndpoint: String {
        switch selectedSpeechProvider {
        case .deepgram:
            configuration.deepgramSpeechEndpoint
        case .whisper:
            configuration.openAISpeechEndpoint
        case .localWhisper:
            localWhisperModelStore.resolvedModelURL(preferredModelName: configuration.localWhisperModel)?.path
                ?? localWhisperModelStore.modelsDirectory.path
        case .localSenseVoice:
            senseVoiceModelStore.resolvedModelDirectory(preferredModelName: configuration.localSenseVoiceModel)?.path
                ?? senseVoiceModelStore.modelsDirectory.path
        }
    }

    var currentSpeechCredentialStatus: CredentialStatus {
        switch selectedSpeechProvider {
        case .deepgram:
            deepgramCredentialStatus
        case .whisper:
            openAICredentialStatus
        case .localWhisper:
            localWhisperCredentialStatus
        case .localSenseVoice:
            localSenseVoiceCredentialStatus
        }
    }

    var currentSpeechCredentialLabel: String {
        selectedSpeechProvider.credentialLabel
    }

    var currentSpeechHint: String {
        switch selectedSpeechProvider {
        case .deepgram:
            "录音结束后上传给 Deepgram 进行整段转写。"
        case .whisper:
            "录音结束后上传给 Whisper 进行整段转写；与研究/轻润色共用同一 API Key 和网关。"
        case .localWhisper:
            "录音结束后直接在本机使用 Whisper ggml 模型转写，不依赖云端转写服务。"
        case .localSenseVoice:
            "录音结束后直接在本机使用 SenseVoice Small 转写，优先走 CPU，本地失败时再回退云端。"
        }
    }

    func currentSpeechConfiguration(base: LiveTranscriptionConfiguration) -> LiveTranscriptionConfiguration {
        switch selectedSpeechProvider {
        case .deepgram:
            LiveTranscriptionConfiguration(
                endpoint: URL(string: configuration.deepgramSpeechEndpoint) ?? base.endpoint,
                model: normalizedOrFallback(configuration.deepgramSpeechModel, fallback: base.model),
                language: normalizedOrFallback(configuration.deepgramSpeechLanguage, fallback: base.language),
                encoding: base.encoding,
                sampleRate: base.sampleRate,
                channels: base.channels,
                interimResults: base.interimResults,
                punctuate: base.punctuate,
                smartFormat: base.smartFormat,
                vadEvents: base.vadEvents,
                endpointingMilliseconds: base.endpointingMilliseconds,
                utteranceEndMilliseconds: base.utteranceEndMilliseconds,
                keywords: base.keywords
            )
        case .whisper:
            LiveTranscriptionConfiguration(
                endpoint: StoredConfiguration.whisperEndpoint(fromResponsesEndpoint: configuration.researchEndpoint)
                    ?? URL(string: configuration.openAISpeechEndpoint)
                    ?? URL(string: StoredConfiguration.defaultTranscriptionsEndpoint)!,
                model: normalizedOrFallback(configuration.openAISpeechModel, fallback: "whisper-1"),
                language: normalizedOrFallback(configuration.openAISpeechLanguage, fallback: "zh"),
                encoding: base.encoding,
                sampleRate: base.sampleRate,
                channels: base.channels,
                interimResults: false,
                punctuate: true,
                smartFormat: true,
                vadEvents: false,
                endpointingMilliseconds: base.endpointingMilliseconds,
                utteranceEndMilliseconds: base.utteranceEndMilliseconds,
                keywords: []
            )
        case .localWhisper:
            LiveTranscriptionConfiguration(
                endpoint: localWhisperModelStore.resolvedModelURL(preferredModelName: configuration.localWhisperModel)
                    ?? localWhisperModelStore.modelURL(forModelNamed: configuration.localWhisperModel),
                model: normalizedOrFallback(
                    configuration.localWhisperModel,
                    fallback: StoredConfiguration.defaultLocalWhisperModel
                ),
                language: normalizedOrFallback(
                    configuration.localWhisperLanguage,
                    fallback: StoredConfiguration.defaultLocalWhisperLanguage
                ),
                encoding: base.encoding,
                sampleRate: base.sampleRate,
                channels: base.channels,
                interimResults: false,
                punctuate: true,
                smartFormat: true,
                vadEvents: false,
                endpointingMilliseconds: base.endpointingMilliseconds,
                utteranceEndMilliseconds: base.utteranceEndMilliseconds,
                keywords: []
            )
        case .localSenseVoice:
            LiveTranscriptionConfiguration(
                endpoint: senseVoiceModelStore.resolvedModelDirectory(
                    preferredModelName: configuration.localSenseVoiceModel
                ) ?? senseVoiceModelStore.modelDirectory(forModelNamed: configuration.localSenseVoiceModel),
                model: normalizedOrFallback(
                    configuration.localSenseVoiceModel,
                    fallback: StoredConfiguration.defaultLocalSenseVoiceModel
                ),
                language: normalizedOrFallback(
                    configuration.localSenseVoiceLanguage,
                    fallback: StoredConfiguration.defaultLocalSenseVoiceLanguage
                ),
                encoding: base.encoding,
                sampleRate: base.sampleRate,
                channels: base.channels,
                interimResults: false,
                punctuate: true,
                smartFormat: true,
                vadEvents: false,
                endpointingMilliseconds: base.endpointingMilliseconds,
                utteranceEndMilliseconds: base.utteranceEndMilliseconds,
                keywords: []
            )
        }
    }

    func refreshCredentialStatus() {
        deepgramCredentialStatus = deepgramCredentialProvider.credentialStatus()
        openAICredentialStatus = openAICredentialProvider.credentialStatus()
        localWhisperCredentialStatus = localWhisperModelStore.resolvedModelURL(
            preferredModelName: configuration.localWhisperModel
        ) == nil ? .missing : .available
        localSenseVoiceCredentialStatus = (
            senseVoiceModelStore.resolvedModelDirectory(preferredModelName: configuration.localSenseVoiceModel) != nil &&
            senseVoiceModelStore.isRuntimeInstalled
        ) ? .available : .missing
    }

    func saveDeepgramAPIKey() throws {
        let trimmed = deepgramAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try deepgramCredentialProvider.save(apiKey: trimmed)
        deepgramAPIKeyInput = ""
        refreshCredentialStatus()
    }

    func removeDeepgramAPIKey() throws {
        try deepgramCredentialProvider.deleteAPIKey()
        refreshCredentialStatus()
    }

    func saveOpenAIAPIKey() throws {
        let trimmed = openAIAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try openAICredentialProvider.save(apiKey: trimmed)
        openAIAPIKeyInput = ""
        refreshCredentialStatus()
    }

    func removeOpenAIAPIKey() throws {
        try openAICredentialProvider.deleteAPIKey()
        refreshCredentialStatus()
    }

    func activateDefaultLocalWhisperModel() {
        configuration.localWhisperModel = localWhisperModelStore.defaultModel.name
        configuration.localWhisperLanguage = localWhisperModelStore.defaultModel.defaultLanguage
        configuration.speechProvider = .localWhisper
        refreshCredentialStatus()
    }

    func activateDefaultSenseVoiceModel() {
        configuration.localSenseVoiceModel = senseVoiceModelStore.defaultModel.name
        configuration.localSenseVoiceLanguage = senseVoiceModelStore.defaultModel.defaultLanguage
        configuration.speechProvider = .localSenseVoice
        refreshCredentialStatus()
    }

    func researchConfiguration() async -> OpenAIResponsesRequestConfiguration {
        let normalized = StoredConfiguration.normalized(configuration)
        return OpenAIResponsesRequestConfiguration(
            endpoint: URL(string: normalized.researchEndpoint) ?? URL(string: StoredConfiguration.defaultResponsesEndpoint)!,
            model: normalized.researchModel,
            timeoutInterval: 30
        )
    }

    func polishConfiguration() async -> OpenAIResponsesRequestConfiguration {
        let normalized = StoredConfiguration.normalized(configuration)
        return OpenAIResponsesRequestConfiguration(
            endpoint: URL(string: normalized.researchEndpoint) ?? URL(string: StoredConfiguration.defaultResponsesEndpoint)!,
            model: normalized.polishModel,
            timeoutInterval: 2.5
        )
    }

    private func bindPersistence() {
        $configuration
            .dropFirst()
            .sink { [weak self] configuration in
                guard let self, !self.isApplyingNormalizedConfiguration else { return }
                self.save(configuration: configuration)
            }
            .store(in: &cancellables)
    }

    private func save(configuration: StoredConfiguration) {
        let normalized = StoredConfiguration.normalized(configuration)
        if normalized != configuration {
            isApplyingNormalizedConfiguration = true
            self.configuration = normalized
            isApplyingNormalizedConfiguration = false
        }
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: Keys.configuration)
        }
    }

    private func normalizedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    enum Keys {
        static let configuration = "model.openaiConfiguration"
    }
}
