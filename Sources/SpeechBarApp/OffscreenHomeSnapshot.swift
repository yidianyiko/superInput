import AppKit
import Foundation
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import MemoryDomain
import SwiftUI

enum OffscreenHomeSnapshotRuntime {
    static let command = OffscreenHomeSnapshotCommand.parse(arguments: CommandLine.arguments)
}

struct OffscreenHomeSnapshotCommand: Sendable {
    let outputURL: URL
    let section: SectionOverride?
    let theme: ThemeOverride?
    let memoryScenario: MemoryScenario
    let memoryDisplayMode: MemoryConstellationDisplayMode?
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat

    enum SectionOverride: String, Sendable {
        case home
        case memory
        case model
        case monitor
        case debug
        case settings
    }

    enum ThemeOverride: String, Sendable {
        case green
        case volt
        case apple
        case sunrise
        case ocean
        case forest
        case graphite
    }

    static func parse(arguments: [String]) -> Self? {
        guard let commandIndex = arguments.firstIndex(of: "--render-home-snapshot") else {
            return nil
        }

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }

        let fallbackOutput = URL(fileURLWithPath: "dist/offscreen-ui/home.png", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let outputURL: URL
        if commandIndex + 1 < arguments.count, !arguments[commandIndex + 1].hasPrefix("--") {
            outputURL = URL(fileURLWithPath: arguments[commandIndex + 1]).standardizedFileURL
        } else {
            outputURL = fallbackOutput.standardizedFileURL
        }

        let section = value(after: "--section")
            .flatMap { SectionOverride(rawValue: $0.lowercased()) }
        let theme = value(after: "--theme")
            .flatMap { ThemeOverride(rawValue: $0.lowercased()) }
        let memoryScenario = Self.parseCaseInsensitive(value(after: "--memory-scenario"), as: MemoryScenario.self) ?? .default
        let memoryDisplayMode = Self.parseCaseInsensitive(value(after: "--memory-display-mode"), as: MemoryConstellationDisplayMode.self)
        let width = value(after: "--width").flatMap(Double.init) ?? 1240
        let height = value(after: "--height").flatMap(Double.init) ?? 780
        let scale = value(after: "--scale").flatMap(Double.init) ?? 2

        return Self(
            outputURL: outputURL,
            section: section,
            theme: theme,
            memoryScenario: memoryScenario,
            memoryDisplayMode: memoryDisplayMode,
            width: CGFloat(width),
            height: CGFloat(height),
            scale: CGFloat(scale)
        )
    }

    private static func parseCaseInsensitive<T>(_ value: String?, as type: T.Type) -> T?
    where T: RawRepresentable & CaseIterable, T.RawValue == String {
        guard let value else {
            return nil
        }

        return T.allCases.first {
            $0.rawValue.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

enum OffscreenHomeSnapshotRenderer {
    @MainActor
    static func run(_ command: OffscreenHomeSnapshotCommand) async -> Int32 {
        do {
            try await render(command)
            return 0
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    @MainActor
    private static func render(_ command: OffscreenHomeSnapshotCommand) async throws {
        let defaultsContext = SnapshotDefaultsContext()
        defer { defaultsContext.cleanup() }

        let environment = SnapshotEnvironment(defaults: defaultsContext.defaults, command: command)

        if command.section == .memory {
            await preloadMemoryConstellation(reload: {
                await environment.memoryConstellationStore.reload()
            })
        }

        let rootView = HomeWindowView(
            coordinator: environment.coordinator,
            agentMonitorCoordinator: environment.agentMonitorCoordinator,
            embeddedDisplayCoordinator: environment.embeddedDisplayCoordinator,
            diagnosticsCoordinator: environment.diagnosticsCoordinator,
            store: environment.homeStore,
            userProfileStore: environment.userProfileStore,
            audioInputSettingsStore: environment.audioInputSettingsStore,
            recordingHotkeySettingsStore: environment.recordingHotkeySettingsStore,
            modelSettingsStore: environment.modelSettingsStore,
            polishPlaygroundStore: environment.polishPlaygroundStore,
            localWhisperModelStore: environment.localWhisperModelStore,
            senseVoiceModelStore: environment.senseVoiceModelStore,
            memoryConstellationStore: environment.memoryConstellationStore,
            memoryFeatureFlagStore: environment.memoryFeatureFlagStore,
            pushToTalkSource: environment.pushToTalkSource
        )
        .frame(width: command.width, height: command.height)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: CGSize(width: command.width, height: command.height))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotRenderError.bitmapCreationFailed
        }

        bitmap.size = NSSize(width: command.width, height: command.height)
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotRenderError.pngEncodingFailed
        }

        let outputURL = command.outputURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        print(outputURL.path)
    }

    static func preloadMemoryConstellation(
        reload: @escaping @Sendable () async -> Void
    ) async {
        await reload()
    }
}

private enum SnapshotRenderError: LocalizedError {
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .bitmapCreationFailed:
            return "Could not create a bitmap representation for the offscreen view."
        case .pngEncodingFailed:
            return "Could not encode the offscreen snapshot as PNG."
        }
    }
}

@MainActor
private final class SnapshotEnvironment {
    let defaults: UserDefaults
    let pushToTalkSource: OnScreenPushToTalkSource
    let coordinator: VoiceSessionCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let recordingHotkeySettingsStore: RecordingHotkeySettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let polishPlaygroundStore: PolishPlaygroundStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let memoryFeatureFlagStore: MemoryFeatureFlagStore
    let memoryConstellationStore: MemoryConstellationStore
    let homeStore: HomeWindowStore

    init(defaults: UserDefaults, command: OffscreenHomeSnapshotCommand) {
        self.defaults = defaults
        self.pushToTalkSource = OnScreenPushToTalkSource()
        let snapshotNow = Date(timeIntervalSince1970: 100)

        let localWhisperModelStore = LocalWhisperModelStore(defaults: defaults)
        localWhisperModelStore.prepareForLaunch(showFirstInstallPrompt: false)
        self.localWhisperModelStore = localWhisperModelStore

        let senseVoiceModelStore = SenseVoiceModelStore(defaults: defaults)
        senseVoiceModelStore.prepareForLaunch(showFirstInstallPrompt: false)
        self.senseVoiceModelStore = senseVoiceModelStore

        let deepgramCredentialProvider = LocalCredentialProvider(defaults: defaults)
        let openAICredentialProvider = LocalCredentialProvider(
            account: "openai-api-key",
            defaults: defaults
        )
        let localWhisperCredentialProvider = LocalWhisperModelCredentialProvider(
            defaults: defaults,
            localWhisperModelsDirectory: localWhisperModelStore.modelsDirectory,
            defaultLocalWhisperModelName: localWhisperModelStore.defaultModel.name
        )
        let localSenseVoiceCredentialProvider = LocalSenseVoiceModelCredentialProvider(
            defaults: defaults,
            localSenseVoiceModelsDirectory: senseVoiceModelStore.modelsDirectory,
            defaultLocalSenseVoiceModelName: senseVoiceModelStore.defaultModel.name,
            senseVoiceRuntimeDirectory: senseVoiceModelStore.runtimeDirectory
        )
        self.modelSettingsStore = OpenAIModelSettingsStore(
            defaults: defaults,
            deepgramCredentialProvider: deepgramCredentialProvider,
            openAICredentialProvider: openAICredentialProvider,
            localWhisperModelStore: localWhisperModelStore,
            senseVoiceModelStore: senseVoiceModelStore
        )
        self.polishPlaygroundStore = PolishPlaygroundStore { transcript in
            transcript
        }

        let credentialProvider = SwitchingSpeechCredentialProvider(
            defaults: defaults,
            deepgramCredentialProvider: deepgramCredentialProvider,
            openAICredentialProvider: openAICredentialProvider,
            localWhisperCredentialProvider: localWhisperCredentialProvider,
            localSenseVoiceCredentialProvider: localSenseVoiceCredentialProvider
        )

        self.userProfileStore = UserProfileStore(defaults: defaults)
        self.audioInputSettingsStore = AudioInputSettingsStore(defaults: defaults)
        let recordingHotkeyController = SnapshotRecordingHotkeySettingsController(
            configuration: RecordingHotkeySettingsStore.loadConfiguration(from: defaults)
        )
        self.recordingHotkeySettingsStore = RecordingHotkeySettingsStore(
            defaults: defaults,
            controller: recordingHotkeyController
        )
        self.memoryFeatureFlagStore = MemoryFeatureFlagStore(defaults: defaults)
        if let memoryDisplayMode = command.memoryDisplayMode {
            self.memoryFeatureFlagStore.displayMode = memoryDisplayMode
        }

        let memoryCatalog: (any MemoryCatalogProviding)?
        switch command.memoryScenario {
        case .live:
            memoryCatalog = nil
        default:
            memoryCatalog = MemoryConstellationFixtures.catalogProvider(for: command.memoryScenario, now: snapshotNow)
        }
        self.memoryConstellationStore = MemoryConstellationStore(
            catalog: memoryCatalog,
            featureFlags: memoryFeatureFlagStore,
            builder: MemoryConstellationBuilder(now: { snapshotNow })
        )
        self.diagnosticsCoordinator = DiagnosticsCoordinator(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("slashvibe-offscreen-diagnostics", isDirectory: true)
        )

        let reducer = DefaultAgentStateReducer(
            staleThreshold: 30,
            purgeThreshold: 3_600
        )
        let snapshotBuilder = DefaultTaskBoardSnapshotBuilder(reducer: reducer)
        self.agentMonitorCoordinator = AgentMonitorCoordinator(
            collectors: [],
            reducer: reducer,
            snapshotBuilder: snapshotBuilder,
            diagnostics: diagnosticsCoordinator
        )

        self.coordinator = VoiceSessionCoordinator(
            hardwareSource: SnapshotHardwareEventSource(),
            audioInputSource: SnapshotAudioInputSource(),
            transcriptionClient: SnapshotTranscriptionClient(),
            credentialProvider: credentialProvider,
            transcriptPublisher: InMemoryTranscriptPublisher(),
            userProfileProvider: userProfileStore
        )

        self.embeddedDisplayCoordinator = EmbeddedDisplayCoordinator(
            voiceCoordinator: coordinator,
            monitorCoordinator: agentMonitorCoordinator,
            diagnostics: diagnosticsCoordinator,
            displayBuilder: DefaultEmbeddedDisplaySnapshotBuilder(),
            encoder: EmbeddedDisplayEncoder(),
            transport: LoopbackBoardTransport()
        )

        self.homeStore = HomeWindowStore(
            coordinator: coordinator,
            defaults: defaults
        )

        if let section = command.section.flatMap(Self.mapSection(from:)) {
            self.homeStore.saveSelectedSection(section)
        }

        if let theme = command.theme?.themePreset {
            self.homeStore.selectedTheme = theme
        }
    }

    private static func mapSection(from override: OffscreenHomeSnapshotCommand.SectionOverride) -> HomeWindowStore.Section {
        switch override {
        case .home:
            return .home
        case .memory:
            return .memory
        case .model:
            return .model
        case .monitor:
            return .monitor
        case .debug:
            return .debug
        case .settings:
            return .settings
        }
    }

}

extension OffscreenHomeSnapshotCommand.ThemeOverride {
    var themePreset: HomeWindowStore.ThemePreset {
        switch self {
        case .green, .volt:
            return .green
        case .apple:
            return .apple
        case .sunrise:
            return .sunrise
        case .ocean:
            return .ocean
        case .forest:
            return .forest
        case .graphite:
            return .graphite
        }
    }
}

@MainActor
private final class SnapshotDefaultsContext {
    let suiteName = "com.slashvibe.offscreen.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create temporary UserDefaults suite for offscreen snapshot.")
        }

        self.defaults = defaults
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct SnapshotHardwareEventSource: HardwareEventSource {
    let events = AsyncStream<HardwareEvent> { _ in }
}

private actor SnapshotAudioInputSource: AudioInputSource {
    nonisolated let audioLevels = AsyncStream<AudioLevelSample> { _ in }

    func requestRecordPermission() async -> AudioInputPermissionStatus {
        .granted
    }

    func startCapture() async throws -> AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stopCapture() async {}
}

private actor SnapshotTranscriptionClient: TranscriptionClient {
    nonisolated let events = AsyncStream<TranscriptEvent> { _ in }

    func connect(apiKey: String, configuration: LiveTranscriptionConfiguration) async throws {}
    func send(audioChunk: AudioChunk) async throws {}
    func finalize() async throws {}
    func close() async {}
}

private final class SnapshotRecordingHotkeySettingsController: RecordingHotkeySettingsControlling, @unchecked Sendable {
    let diagnosticsUpdates: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>

    private let diagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation

    private(set) var diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot

    init(configuration: RecordingHotkeyConfiguration) {
        var capturedDiagnosticsContinuation: AsyncStream<RecordingHotkeyDiagnosticsSnapshot>.Continuation?
        self.diagnosticsUpdates = AsyncStream { continuation in
            capturedDiagnosticsContinuation = continuation
        }
        self.diagnosticsContinuation = capturedDiagnosticsContinuation!
        self.diagnosticsSnapshot = Self.makeSnapshot(configuration: configuration)
    }

    func apply(_ configuration: RecordingHotkeyConfiguration) {
        diagnosticsSnapshot = Self.makeSnapshot(configuration: configuration)
        diagnosticsContinuation.yield(diagnosticsSnapshot)
    }

    private static func makeSnapshot(configuration: RecordingHotkeyConfiguration) -> RecordingHotkeyDiagnosticsSnapshot {
        let requiresAccessibility = configuration.mode == .rightCommand
        return RecordingHotkeyDiagnosticsSnapshot(
            configuration: configuration,
            registrationStatus: .registered,
            requiresAccessibility: requiresAccessibility,
            accessibilityTrusted: true,
            lastTrigger: nil,
            guidanceText: nil
        )
    }
}
