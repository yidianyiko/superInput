import Foundation
import SpeechBarDomain
import SpeechBarInfrastructure

private func switchableSpeechDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) [SwitchableSpeech] \(message)\n"
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

private struct LocalWhisperModelLocator: Sendable {
    let modelsDirectory: URL
    let defaultModelName: String

    func credentialStatus(preferredModelName: String?) -> CredentialStatus {
        resolvedModelURL(preferredModelName: preferredModelName) == nil ? .missing : .available
    }

    func resolvedModelURL(preferredModelName: String?) -> URL? {
        let fileManager = FileManager.default

        let normalizedPreferred = preferredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPreferred, !normalizedPreferred.isEmpty {
            let preferredURL = modelURL(forModelNamed: normalizedPreferred)
            if fileManager.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let defaultURL = modelURL(forModelNamed: defaultModelName)
        if fileManager.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }

        let installedModelURLs = (try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        return installedModelURLs
            .filter { $0.pathExtension.lowercased() == "bin" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    func modelURL(forModelNamed name: String) -> URL {
        modelsDirectory.appendingPathComponent("\(name).bin")
    }
}

private struct SenseVoiceModelLocator: Sendable {
    let modelsDirectory: URL
    let defaultModelName: String

    func credentialStatus(preferredModelName: String?) -> CredentialStatus {
        resolvedModelDirectory(preferredModelName: preferredModelName) == nil ? .missing : .available
    }

    func resolvedModelDirectory(preferredModelName: String?) -> URL? {
        let fileManager = FileManager.default
        let normalizedPreferred = preferredModelName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPreferred, !normalizedPreferred.isEmpty {
            let preferredURL = modelDirectory(forModelNamed: normalizedPreferred)
            if isValidModelDirectory(preferredURL, fileManager: fileManager) {
                return preferredURL
            }
        }

        let defaultURL = modelDirectory(forModelNamed: defaultModelName)
        if isValidModelDirectory(defaultURL, fileManager: fileManager) {
            return defaultURL
        }

        let installedModelURLs = (try? fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        return installedModelURLs
            .filter { isValidModelDirectory($0, fileManager: fileManager) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    func modelDirectory(forModelNamed name: String) -> URL {
        modelsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private func isValidModelDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        let tokensURL = url.appendingPathComponent("tokens.txt")
        guard fileManager.fileExists(atPath: tokensURL.path) else {
            return false
        }

        let readyMarkerURL = url.appendingPathComponent(".ready")
        guard fileManager.fileExists(atPath: readyMarkerURL.path) else {
            return false
        }

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )) ?? []

        return fileURLs.contains {
            let filename = $0.lastPathComponent.lowercased()
            return filename.hasSuffix(".onnx") && filename.contains("model")
        }
    }
}

final class SwitchingSpeechCredentialProvider: CredentialProvider, @unchecked Sendable {
    private let defaults: UserDefaults
    private let deepgramCredentialProvider: any CredentialProvider
    private let openAICredentialProvider: any CredentialProvider
    private let localWhisperCredentialProvider: any CredentialProvider
    private let localSenseVoiceCredentialProvider: any CredentialProvider

    init(
        defaults: UserDefaults = .standard,
        deepgramCredentialProvider: any CredentialProvider,
        openAICredentialProvider: any CredentialProvider,
        localWhisperCredentialProvider: any CredentialProvider,
        localSenseVoiceCredentialProvider: any CredentialProvider
    ) {
        self.defaults = defaults
        self.deepgramCredentialProvider = deepgramCredentialProvider
        self.openAICredentialProvider = openAICredentialProvider
        self.localWhisperCredentialProvider = localWhisperCredentialProvider
        self.localSenseVoiceCredentialProvider = localSenseVoiceCredentialProvider
    }

    func credentialStatus() -> CredentialStatus {
        activeProvider().credentialStatus()
    }

    func loadAPIKey() throws -> String {
        try activeProvider().loadAPIKey()
    }

    func save(apiKey: String) throws {
        try activeProvider().save(apiKey: apiKey)
    }

    func deleteAPIKey() throws {
        try activeProvider().deleteAPIKey()
    }

    private func activeProvider() -> any CredentialProvider {
        switch OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults).speechProvider {
        case .deepgram:
            deepgramCredentialProvider
        case .whisper:
            openAICredentialProvider
        case .localWhisper:
            localWhisperCredentialProvider
        case .localSenseVoice:
            localSenseVoiceCredentialProvider
        }
    }
}

enum LocalWhisperModelCredentialError: LocalizedError {
    case missingInstalledModel

    var errorDescription: String? {
        switch self {
        case .missingInstalledModel:
            return "本地 Whisper 模型尚未安装。先完成默认模型下载，再开始录音。"
        }
    }
}

enum LocalSenseVoiceModelCredentialError: LocalizedError {
    case missingInstalledModel

    var errorDescription: String? {
        switch self {
        case .missingInstalledModel:
            return "SenseVoice 模型或运行时尚未安装。先完成默认安装，再开始录音。"
        }
    }
}

final class LocalWhisperModelCredentialProvider: CredentialProvider, @unchecked Sendable {
    private let defaults: UserDefaults
    private let modelLocator: LocalWhisperModelLocator

    init(
        defaults: UserDefaults = .standard,
        localWhisperModelsDirectory: URL,
        defaultLocalWhisperModelName: String
    ) {
        self.defaults = defaults
        self.modelLocator = LocalWhisperModelLocator(
            modelsDirectory: localWhisperModelsDirectory,
            defaultModelName: defaultLocalWhisperModelName
        )
    }

    func credentialStatus() -> CredentialStatus {
        let storedConfiguration = OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults)
        return modelLocator.credentialStatus(preferredModelName: storedConfiguration.localWhisperModel)
    }

    func loadAPIKey() throws -> String {
        guard credentialStatus() == .available else {
            throw LocalWhisperModelCredentialError.missingInstalledModel
        }
        return "local-whisper-model"
    }

    func save(apiKey: String) throws {}

    func deleteAPIKey() throws {}
}

final class LocalSenseVoiceModelCredentialProvider: CredentialProvider, @unchecked Sendable {
    private let defaults: UserDefaults
    private let modelLocator: SenseVoiceModelLocator
    private let runtimeDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        localSenseVoiceModelsDirectory: URL,
        defaultLocalSenseVoiceModelName: String,
        senseVoiceRuntimeDirectory: URL
    ) {
        self.defaults = defaults
        self.modelLocator = SenseVoiceModelLocator(
            modelsDirectory: localSenseVoiceModelsDirectory,
            defaultModelName: defaultLocalSenseVoiceModelName
        )
        self.runtimeDirectory = senseVoiceRuntimeDirectory
    }

    func credentialStatus() -> CredentialStatus {
        let storedConfiguration = OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults)
        let hasModel = modelLocator.credentialStatus(preferredModelName: storedConfiguration.localSenseVoiceModel) == .available
        let pythonURL = runtimeDirectory.appendingPathComponent("bin/python3")
        let runtimeMarkerURL = runtimeDirectory.appendingPathComponent(".runtime-ready")
        let hasRuntime =
            FileManager.default.fileExists(atPath: pythonURL.path) &&
            FileManager.default.fileExists(atPath: runtimeMarkerURL.path)
        return hasModel && hasRuntime ? .available : .missing
    }

    func loadAPIKey() throws -> String {
        guard credentialStatus() == .available else {
            throw LocalSenseVoiceModelCredentialError.missingInstalledModel
        }
        return "local-sensevoice-model"
    }

    func save(apiKey: String) throws {}

    func deleteAPIKey() throws {}
}

actor SwitchableSpeechTranscriptionClient: TranscriptionClient {
    nonisolated let events: AsyncStream<TranscriptEvent>

    private let continuation: AsyncStream<TranscriptEvent>.Continuation
    private let defaults: UserDefaults
    private let deepgramClient: any TranscriptionClient
    private let whisperClient: any TranscriptionClient
    private let localWhisperClient: any TranscriptionClient
    private let localSenseVoiceClient: any TranscriptionClient
    private let localWhisperModelLocator: LocalWhisperModelLocator
    private let senseVoiceModelLocator: SenseVoiceModelLocator
    private let localWhisperFinalizeTimeout: Duration
    private let localSenseVoiceFinalizeTimeout: Duration

    private var activeProvider: SpeechTranscriptionProvider?
    private var activeConfiguration: LiveTranscriptionConfiguration?
    private var preferredConfiguration: OpenAIModelSettingsStore.StoredConfiguration?
    private var capturedAudioChunks: [AudioChunk] = []

    init(
        defaults: UserDefaults = .standard,
        deepgramClient: any TranscriptionClient,
        whisperClient: any TranscriptionClient,
        localWhisperClient: any TranscriptionClient,
        localSenseVoiceClient: any TranscriptionClient,
        localWhisperModelsDirectory: URL,
        defaultLocalWhisperModelName: String,
        localSenseVoiceModelsDirectory: URL,
        defaultLocalSenseVoiceModelName: String,
        localWhisperFinalizeTimeout: Duration = .seconds(8),
        localSenseVoiceFinalizeTimeout: Duration = .seconds(8)
    ) {
        self.defaults = defaults
        self.deepgramClient = deepgramClient
        self.whisperClient = whisperClient
        self.localWhisperClient = localWhisperClient
        self.localSenseVoiceClient = localSenseVoiceClient
        self.localWhisperModelLocator = LocalWhisperModelLocator(
            modelsDirectory: localWhisperModelsDirectory,
            defaultModelName: defaultLocalWhisperModelName
        )
        self.senseVoiceModelLocator = SenseVoiceModelLocator(
            modelsDirectory: localSenseVoiceModelsDirectory,
            defaultModelName: defaultLocalSenseVoiceModelName
        )
        self.localWhisperFinalizeTimeout = localWhisperFinalizeTimeout
        self.localSenseVoiceFinalizeTimeout = localSenseVoiceFinalizeTimeout

        var capturedContinuation: AsyncStream<TranscriptEvent>.Continuation?
        self.events = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation!

        Task { [weak self] in
            for await event in deepgramClient.events {
                await self?.forward(event: event, from: .deepgram)
            }
        }

        Task { [weak self] in
            for await event in whisperClient.events {
                await self?.forward(event: event, from: .whisper)
            }
        }

        Task { [weak self] in
            for await event in localWhisperClient.events {
                await self?.forward(event: event, from: .localWhisper)
            }
        }

        Task { [weak self] in
            for await event in localSenseVoiceClient.events {
                await self?.forward(event: event, from: .localSenseVoice)
            }
        }
    }

    func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {
        let storedConfiguration = OpenAIModelSettingsStore.StoredConfiguration.load(from: defaults)
        preferredConfiguration = storedConfiguration
        capturedAudioChunks = []
        try await connect(
            provider: storedConfiguration.speechProvider,
            apiKey: apiKey,
            storedConfiguration: storedConfiguration,
            baseConfiguration: configuration
        )
    }

    func send(audioChunk: AudioChunk) async throws {
        capturedAudioChunks.append(audioChunk)
        switch activeProvider {
        case .deepgram:
            try await deepgramClient.send(audioChunk: audioChunk)
        case .whisper:
            try await whisperClient.send(audioChunk: audioChunk)
        case .localWhisper:
            try await localWhisperClient.send(audioChunk: audioChunk)
        case .localSenseVoice:
            try await localSenseVoiceClient.send(audioChunk: audioChunk)
        case .none:
            break
        }
    }

    func finalize() async throws {
        guard let activeProvider else { return }

        do {
            try await finalize(provider: activeProvider)
        } catch {
            guard let storedConfiguration = preferredConfiguration else {
                throw error
            }

            let failedProvider = activeProvider
            let fallbackProviders = fallbackProviders(after: activeProvider, error: error)
            guard !fallbackProviders.isEmpty else {
                throw error
            }
            let candidateNames = fallbackProviders.map { $0.rawValue }.joined(separator: ",")

            switchableSpeechDebugLog(
                "provider=\(failedProvider.rawValue) finalize failed, fallback candidates=\(candidateNames), error=\(String(describing: error))"
            )

            var lastError = error
            for fallbackProvider in fallbackProviders {
                do {
                    try await reconnectAndReplay(
                        to: fallbackProvider,
                        storedConfiguration: storedConfiguration
                    )
                    try await finalize(provider: fallbackProvider)
                    switchableSpeechDebugLog(
                        "provider fallback succeeded from \(failedProvider.rawValue) to \(fallbackProvider.rawValue)"
                    )
                    return
                } catch {
                    lastError = error
                    switchableSpeechDebugLog(
                        "provider fallback failed target=\(fallbackProvider.rawValue), error=\(String(describing: error))"
                    )
                }
            }

            throw lastError
        }
    }

    func close() async {
        activeProvider = nil
        activeConfiguration = nil
        preferredConfiguration = nil
        capturedAudioChunks = []
        await deepgramClient.close()
        await whisperClient.close()
        await localWhisperClient.close()
        await localSenseVoiceClient.close()
    }

    private func forward(event: TranscriptEvent, from provider: SpeechTranscriptionProvider) {
        guard activeProvider == provider else { return }
        continuation.yield(event)
    }

    private func connect(
        provider: SpeechTranscriptionProvider,
        apiKey: String,
        storedConfiguration: OpenAIModelSettingsStore.StoredConfiguration,
        baseConfiguration: LiveTranscriptionConfiguration
    ) async throws {
        let resolvedConfiguration = resolvedConfiguration(
            for: provider,
            from: storedConfiguration,
            base: baseConfiguration
        )
        activeProvider = provider
        activeConfiguration = baseConfiguration

        switch provider {
        case .deepgram:
            try await deepgramClient.connect(apiKey: apiKey, configuration: resolvedConfiguration)
        case .whisper:
            try await whisperClient.connect(apiKey: apiKey, configuration: resolvedConfiguration)
        case .localWhisper:
            try await localWhisperClient.connect(apiKey: apiKey, configuration: resolvedConfiguration)
        case .localSenseVoice:
            try await localSenseVoiceClient.connect(apiKey: apiKey, configuration: resolvedConfiguration)
        }
    }

    private func reconnectAndReplay(
        to provider: SpeechTranscriptionProvider,
        storedConfiguration: OpenAIModelSettingsStore.StoredConfiguration
    ) async throws {
        guard let activeConfiguration else { return }

        await client(for: activeProvider).close()
        let apiKey = try loadAPIKey(for: provider, storedConfiguration: storedConfiguration)
        try await connect(
            provider: provider,
            apiKey: apiKey,
            storedConfiguration: storedConfiguration,
            baseConfiguration: activeConfiguration
        )

        for chunk in capturedAudioChunks {
            try await client(for: provider).send(audioChunk: chunk)
        }
    }

    private func finalize(provider: SpeechTranscriptionProvider) async throws {
        switch provider {
        case .deepgram:
            try await deepgramClient.finalize()
        case .whisper:
            try await whisperClient.finalize()
        case .localWhisper:
            try await withTimeout(localWhisperFinalizeTimeout) {
                try await self.localWhisperClient.finalize()
            }
        case .localSenseVoice:
            try await withTimeout(localSenseVoiceFinalizeTimeout) {
                try await self.localSenseVoiceClient.finalize()
            }
        }
    }

    private func fallbackProviders(
        after provider: SpeechTranscriptionProvider,
        error: Error
    ) -> [SpeechTranscriptionProvider] {
        switch provider {
        case .whisper:
            guard shouldFallbackFromWhisper(error: error), hasCredentialOrModel(for: .deepgram) else {
                return []
            }
            return [.deepgram]
        case .localWhisper:
            guard hasCredentialOrModel(for: .deepgram) else { return [] }
            return [.deepgram]
        case .localSenseVoice:
            guard hasCredentialOrModel(for: .deepgram) else { return [] }
            return [.deepgram]
        case .deepgram:
            return []
        }
    }

    private func shouldFallbackFromWhisper(error: Error) -> Bool {
        guard let whisperError = error as? OpenAIWhisperTranscriptionClientError else {
            return false
        }

        switch whisperError {
        case .badHTTPStatus(let statusCode, _):
            return statusCode == 429
        case .notConnected, .emptyAudio, .invalidResponse:
            return false
        }
    }

    private func hasCredentialOrModel(for provider: SpeechTranscriptionProvider) -> Bool {
        switch provider {
        case .deepgram:
            let provider = LocalCredentialProvider(defaults: defaults)
            return provider.credentialStatus() == .available
        case .whisper:
            let provider = LocalCredentialProvider(account: "openai-api-key", defaults: defaults)
            return provider.credentialStatus() == .available
        case .localWhisper:
            let preferredModelName = preferredConfiguration?.localWhisperModel
            return localWhisperModelLocator.credentialStatus(preferredModelName: preferredModelName) == .available
        case .localSenseVoice:
            let preferredModelName = preferredConfiguration?.localSenseVoiceModel
            return senseVoiceModelLocator.credentialStatus(preferredModelName: preferredModelName) == .available
        }
    }

    private func loadAPIKey(
        for provider: SpeechTranscriptionProvider,
        storedConfiguration: OpenAIModelSettingsStore.StoredConfiguration
    ) throws -> String {
        switch provider {
        case .deepgram:
            return try LocalCredentialProvider(defaults: defaults).loadAPIKey()
        case .whisper:
            return try LocalCredentialProvider(account: "openai-api-key", defaults: defaults).loadAPIKey()
        case .localWhisper:
            guard hasCredentialOrModel(for: .localWhisper) else {
                let modelURL = localWhisperModelLocator.modelURL(forModelNamed: storedConfiguration.localWhisperModel)
                throw LocalWhisperTranscriptionClientError.missingModel(modelURL)
            }
            return "local-whisper-model"
        case .localSenseVoice:
            guard hasCredentialOrModel(for: .localSenseVoice) else {
                let modelURL = senseVoiceModelLocator.modelDirectory(forModelNamed: storedConfiguration.localSenseVoiceModel)
                throw SenseVoiceTranscriptionClientError.missingModel(modelURL)
            }
            return "local-sensevoice-model"
        }
    }

    private func client(for provider: SpeechTranscriptionProvider?) -> any TranscriptionClient {
        switch provider {
        case .deepgram:
            return deepgramClient
        case .whisper:
            return whisperClient
        case .localWhisper:
            return localWhisperClient
        case .localSenseVoice:
            return localSenseVoiceClient
        case .none:
            return deepgramClient
        }
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw LocalWhisperFinalizeTimeoutError(duration: duration)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func resolvedConfiguration(
        for provider: SpeechTranscriptionProvider,
        from storedConfiguration: OpenAIModelSettingsStore.StoredConfiguration,
        base: LiveTranscriptionConfiguration
    ) -> LiveTranscriptionConfiguration {
        switch provider {
        case .deepgram:
            return LiveTranscriptionConfiguration(
                endpoint: URL(string: storedConfiguration.deepgramSpeechEndpoint) ?? base.endpoint,
                model: normalizedOrFallback(storedConfiguration.deepgramSpeechModel, fallback: base.model),
                language: normalizedOrFallback(storedConfiguration.deepgramSpeechLanguage, fallback: base.language),
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
            let endpoint =
                OpenAIModelSettingsStore.StoredConfiguration
                .whisperEndpoint(fromResponsesEndpoint: storedConfiguration.researchEndpoint)
                ?? URL(string: storedConfiguration.openAISpeechEndpoint)
                ?? URL(string: OpenAIModelSettingsStore.StoredConfiguration.defaultTranscriptionsEndpoint)!
            return LiveTranscriptionConfiguration(
                endpoint: endpoint,
                model: normalizedOrFallback(storedConfiguration.openAISpeechModel, fallback: "whisper-1"),
                language: normalizedOrFallback(storedConfiguration.openAISpeechLanguage, fallback: "zh"),
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
            let localModelURL =
                localWhisperModelLocator.resolvedModelURL(
                    preferredModelName: storedConfiguration.localWhisperModel
                ) ?? localWhisperModelLocator.modelURL(forModelNamed: storedConfiguration.localWhisperModel)
            return LiveTranscriptionConfiguration(
                endpoint: localModelURL,
                model: normalizedOrFallback(
                    storedConfiguration.localWhisperModel,
                    fallback: OpenAIModelSettingsStore.StoredConfiguration.defaultLocalWhisperModel
                ),
                language: normalizedOrFallback(
                    storedConfiguration.localWhisperLanguage,
                    fallback: OpenAIModelSettingsStore.StoredConfiguration.defaultLocalWhisperLanguage
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
            let localModelDirectory =
                senseVoiceModelLocator.resolvedModelDirectory(
                    preferredModelName: storedConfiguration.localSenseVoiceModel
                ) ?? senseVoiceModelLocator.modelDirectory(forModelNamed: storedConfiguration.localSenseVoiceModel)
            return LiveTranscriptionConfiguration(
                endpoint: localModelDirectory,
                model: normalizedOrFallback(
                    storedConfiguration.localSenseVoiceModel,
                    fallback: OpenAIModelSettingsStore.StoredConfiguration.defaultLocalSenseVoiceModel
                ),
                language: normalizedOrFallback(
                    storedConfiguration.localSenseVoiceLanguage,
                    fallback: OpenAIModelSettingsStore.StoredConfiguration.defaultLocalSenseVoiceLanguage
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

    private func normalizedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct LocalWhisperFinalizeTimeoutError: LocalizedError {
    let duration: Duration

    var errorDescription: String? {
        "本地 Whisper 推理超时（\(duration.components.seconds)s）。"
    }
}
