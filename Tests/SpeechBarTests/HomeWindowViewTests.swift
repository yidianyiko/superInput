import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("HomeWindowView")
struct HomeWindowViewTests {
    @Test
    @MainActor
    func agentMonitorUpdatesDoNotInvalidateRootViewOutsideMonitorSections() async throws {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.settings)
        var bodyEvaluationCount = 0

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            recordingHotkeySettingsStore: dependencies.recordingHotkeySettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            bodyEvaluationProbe: { bodyEvaluationCount += 1 }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

        hostingView.layoutSubtreeIfNeeded()
        let baselineCount = bodyEvaluationCount

        dependencies.agentMonitorCoordinator.setGlobalBrowseMode(true)
        try await Task.sleep(for: .milliseconds(80))
        hostingView.layoutSubtreeIfNeeded()

        #expect(bodyEvaluationCount == baselineCount)
    }

    @Test
    @MainActor
    func diagnosticsUpdatesDoNotInvalidateRootViewOutsideDebugSections() async throws {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.home)
        var bodyEvaluationCount = 0

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            recordingHotkeySettingsStore: dependencies.recordingHotkeySettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            bodyEvaluationProbe: { bodyEvaluationCount += 1 }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

        hostingView.layoutSubtreeIfNeeded()
        let baselineCount = bodyEvaluationCount

        dependencies.diagnosticsCoordinator.recordDiagnostic(
            subsystem: "test",
            severity: .info,
            message: "trigger update"
        )
        try await Task.sleep(for: .milliseconds(80))
        hostingView.layoutSubtreeIfNeeded()

        #expect(bodyEvaluationCount == baselineCount)
    }

    @Test
    @MainActor
    func recordingHotkeySettingsUpdatesDoNotInvalidateRootViewBeforeConsumption() async throws {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.home)
        var bodyEvaluationCount = 0

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            recordingHotkeySettingsStore: dependencies.recordingHotkeySettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            bodyEvaluationProbe: { bodyEvaluationCount += 1 }
        )
        let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

        hostingView.layoutSubtreeIfNeeded()
        let baselineCount = bodyEvaluationCount

        dependencies.recordingHotkeySettingsStore.setMode(.customCombo)
        try await Task.sleep(for: .milliseconds(80))
        hostingView.layoutSubtreeIfNeeded()

        #expect(bodyEvaluationCount == baselineCount)
    }

    @Test
    @MainActor
    func greenDefaultThemeRendersDarkHomeSurface() {
        let dependencies = makeHomeWindowDependencies()
        dependencies.store.saveSelectedSection(.home)

        let view = HomeWindowView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            store: dependencies.store,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            recordingHotkeySettingsStore: dependencies.recordingHotkeySettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            polishPlaygroundStore: dependencies.polishPlaygroundStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            memoryConstellationStore: dependencies.memoryConstellationStore,
            memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
            pushToTalkSource: dependencies.pushToTalkSource
        )

        let image = renderedBitmap(
            for: view.frame(width: 1240, height: 780),
            size: CGSize(width: 1240, height: 780)
        )

        assertDarkPixel(image, x: 40, y: 40)
        assertDarkPixel(image, x: 1080, y: 150)
    }
}

@MainActor
private func makeHomeWindowDependencies() -> HomeWindowViewTestDependencies {
    let defaults = UserDefaults(suiteName: "HomeWindowViewTests.\(UUID().uuidString)")!
    let diagnosticsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HomeWindowViewTests-\(UUID().uuidString)", isDirectory: true)
    let hardware = MockHardwareEventSource()
    let audio = MockAudioInputSource()
    let client = MockTranscriptionClient()
    let credentials = MockCredentialProvider(storedAPIKey: "test-key")
    let publisher = MockTranscriptPublisher()
    let coordinator = VoiceSessionCoordinator(
        hardwareSource: hardware,
        audioInputSource: audio,
        transcriptionClient: client,
        credentialProvider: credentials,
        transcriptPublisher: publisher,
        sleepClock: ImmediateSleepClock()
    )
    let diagnosticsCoordinator = DiagnosticsCoordinator(baseDirectory: diagnosticsDirectory)
    let reducer = DefaultAgentStateReducer(staleThreshold: 30, purgeThreshold: 3_600)
    let agentMonitorCoordinator = AgentMonitorCoordinator(
        collectors: [],
        reducer: reducer,
        snapshotBuilder: DefaultTaskBoardSnapshotBuilder(reducer: reducer),
        diagnostics: diagnosticsCoordinator
    )
    let embeddedDisplayCoordinator = EmbeddedDisplayCoordinator(
        voiceCoordinator: coordinator,
        monitorCoordinator: agentMonitorCoordinator,
        diagnostics: diagnosticsCoordinator,
        displayBuilder: DefaultEmbeddedDisplaySnapshotBuilder(),
        encoder: EmbeddedDisplayEncoder(),
        transport: LoopbackBoardTransport()
    )
    let pushToTalkSource = OnScreenPushToTalkSource()
    let recordingHotkeySettingsStore = RecordingHotkeySettingsStore(
        defaults: defaults,
        controller: MockRecordingHotkeySettingsController(
            diagnosticsSnapshot: RecordingHotkeyDiagnosticsSnapshot(
                configuration: .defaultRightCommand,
                registrationStatus: .registered,
                requiresAccessibility: true,
                accessibilityTrusted: true,
                lastTrigger: nil,
                guidanceText: nil
            )
        )
    )
    let userProfileStore = UserProfileStore(defaults: defaults)
    let audioInputSettingsStore = AudioInputSettingsStore(defaults: defaults)
    let localWhisperModelStore = LocalWhisperModelStore(defaults: defaults)
    let senseVoiceModelStore = SenseVoiceModelStore(defaults: defaults)
    let modelSettingsStore = OpenAIModelSettingsStore(
        defaults: defaults,
        deepgramCredentialProvider: credentials,
        openAICredentialProvider: credentials,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore
    )
    let polishPlaygroundStore = PolishPlaygroundStore { _ in "" }
    let memoryFeatureFlagStore = MemoryFeatureFlagStore(defaults: defaults)
    let memoryConstellationStore = MemoryConstellationStore(
        catalog: nil,
        featureFlags: memoryFeatureFlagStore
    )
    let store = HomeWindowStore(coordinator: coordinator, defaults: defaults)
    return HomeWindowViewTestDependencies(
        coordinator: coordinator,
        agentMonitorCoordinator: agentMonitorCoordinator,
        embeddedDisplayCoordinator: embeddedDisplayCoordinator,
        diagnosticsCoordinator: diagnosticsCoordinator,
        store: store,
        userProfileStore: userProfileStore,
        audioInputSettingsStore: audioInputSettingsStore,
        recordingHotkeySettingsStore: recordingHotkeySettingsStore,
        modelSettingsStore: modelSettingsStore,
        polishPlaygroundStore: polishPlaygroundStore,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore,
        memoryConstellationStore: memoryConstellationStore,
        memoryFeatureFlagStore: memoryFeatureFlagStore,
        pushToTalkSource: pushToTalkSource
    )
}

@MainActor
private func renderedBitmap<V: View>(for view: V, size: CGSize) -> NSBitmapImageRep {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    return bitmap
}

private func assertDarkPixel(
    _ bitmap: NSBitmapImageRep,
    x: Int,
    y: Int,
    maxBrightness: Double = 0.45,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    #expect(color != nil, sourceLocation: sourceLocation)
    guard let color else {
        return
    }

    let brightness = (Double(color.redComponent) + Double(color.greenComponent) + Double(color.blueComponent)) / 3.0
    #expect(brightness < maxBrightness, sourceLocation: sourceLocation)
}

@MainActor
private struct HomeWindowViewTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let store: HomeWindowStore
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let recordingHotkeySettingsStore: RecordingHotkeySettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let polishPlaygroundStore: PolishPlaygroundStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let memoryConstellationStore: MemoryConstellationStore
    let memoryFeatureFlagStore: MemoryFeatureFlagStore
    let pushToTalkSource: OnScreenPushToTalkSource
}
