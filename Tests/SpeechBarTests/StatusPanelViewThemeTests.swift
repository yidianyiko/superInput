import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("StatusPanelViewTheme")
struct StatusPanelViewThemeTests {
    @Test
    @MainActor
    func defaultThemeRawValueUsesGreenPreset() {
        #expect(StatusPanelView.defaultThemeRawValue == HomeWindowStore.ThemePreset.green.rawValue)
    }

    @Test
    @MainActor
    func resolvesMissingRawValueToGreenPreset() {
        #expect(StatusPanelView.resolvedThemePreset(from: nil) == .green)
    }

    @Test
    @MainActor
    func resolvesUnknownRawValueToGreenPreset() {
        #expect(StatusPanelView.resolvedThemePreset(from: "not-a-theme") == .green)
    }

    @Test
    @MainActor
    func resolvesKnownRawValueWithoutFallback() {
        #expect(StatusPanelView.resolvedThemePreset(from: HomeWindowStore.ThemePreset.forest.rawValue) == .forest)
    }

    @Test
    @MainActor
    func greenDefaultThemeRendersDarkStatusSurface() {
        let defaults = UserDefaults.standard
        let previousTheme = defaults.string(forKey: "home.selectedTheme")
        defaults.set(HomeWindowStore.ThemePreset.green.rawValue, forKey: "home.selectedTheme")
        defer {
            if let previousTheme {
                defaults.set(previousTheme, forKey: "home.selectedTheme")
            } else {
                defaults.removeObject(forKey: "home.selectedTheme")
            }
        }

        let dependencies = makeStatusPanelDependencies()
        let view = StatusPanelView(
            coordinator: dependencies.coordinator,
            agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
            embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
            diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
            userProfileStore: dependencies.userProfileStore,
            audioInputSettingsStore: dependencies.audioInputSettingsStore,
            modelSettingsStore: dependencies.modelSettingsStore,
            localWhisperModelStore: dependencies.localWhisperModelStore,
            senseVoiceModelStore: dependencies.senseVoiceModelStore,
            pushToTalkSource: dependencies.pushToTalkSource,
            openHomeAction: nil
        )

        let bitmap = renderedBitmap(
            for: view.frame(width: 420, height: 560),
            size: CGSize(width: 420, height: 560)
        )

        assertDarkPixel(bitmap, x: 300, y: 40)
        assertDarkPixel(bitmap, x: 300, y: 260)
    }
}

@MainActor
private func makeStatusPanelDependencies() -> StatusPanelViewTestDependencies {
    let defaults = UserDefaults(suiteName: "StatusPanelViewThemeTests.\(UUID().uuidString)")!
    let diagnosticsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StatusPanelViewThemeTests-\(UUID().uuidString)", isDirectory: true)
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
    return StatusPanelViewTestDependencies(
        coordinator: coordinator,
        agentMonitorCoordinator: agentMonitorCoordinator,
        embeddedDisplayCoordinator: embeddedDisplayCoordinator,
        diagnosticsCoordinator: diagnosticsCoordinator,
        userProfileStore: userProfileStore,
        audioInputSettingsStore: audioInputSettingsStore,
        modelSettingsStore: modelSettingsStore,
        localWhisperModelStore: localWhisperModelStore,
        senseVoiceModelStore: senseVoiceModelStore,
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
private struct StatusPanelViewTestDependencies {
    let coordinator: VoiceSessionCoordinator
    let agentMonitorCoordinator: AgentMonitorCoordinator
    let embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    let diagnosticsCoordinator: DiagnosticsCoordinator
    let userProfileStore: UserProfileStore
    let audioInputSettingsStore: AudioInputSettingsStore
    let modelSettingsStore: OpenAIModelSettingsStore
    let localWhisperModelStore: LocalWhisperModelStore
    let senseVoiceModelStore: SenseVoiceModelStore
    let pushToTalkSource: OnScreenPushToTalkSource
}
