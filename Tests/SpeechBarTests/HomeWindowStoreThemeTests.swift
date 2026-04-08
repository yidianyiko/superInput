import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpeechBarApp
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("HomeWindowStoreTheme")
struct HomeWindowStoreThemeTests {
    @Test
    @MainActor
    func freshInstallUsesGreenPresetByDefaultAndPersistsThemeVersion() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        #expect(store.selectedTheme == HomeWindowStore.ThemePreset.green)
        #expect(defaults.string(forKey: "home.selectedTheme") == HomeWindowStore.ThemePreset.green.rawValue)
        #expect(defaults.integer(forKey: "home.themeStyleVersion") == 3)
    }

    @Test
    @MainActor
    func legacyAppleDefaultMigratesToGreenPresetWhenStoredVersionIsTwo() {
        let defaults = makeDefaults()
        defaults.set(HomeWindowStore.ThemePreset.apple.rawValue, forKey: "home.selectedTheme")
        defaults.set(2, forKey: "home.themeStyleVersion")

        let store = makeStore(defaults: defaults)

        #expect(store.selectedTheme == HomeWindowStore.ThemePreset.green)
        #expect(defaults.string(forKey: "home.selectedTheme") == HomeWindowStore.ThemePreset.green.rawValue)
        #expect(defaults.integer(forKey: "home.themeStyleVersion") == 3)
    }

    @Test
    @MainActor
    func legacyNonDefaultThemeRemainsSelectedWhenStoredVersionIsTwo() {
        let defaults = makeDefaults()
        defaults.set(HomeWindowStore.ThemePreset.forest.rawValue, forKey: "home.selectedTheme")
        defaults.set(2, forKey: "home.themeStyleVersion")

        let store = makeStore(defaults: defaults)

        #expect(store.selectedTheme == .forest)
        #expect(defaults.string(forKey: "home.selectedTheme") == HomeWindowStore.ThemePreset.forest.rawValue)
        #expect(defaults.integer(forKey: "home.themeStyleVersion") == 3)
    }

    @Test
    @MainActor
    func unknownStoredThemeRawAtCurrentVersionIsNotClobberedOnInit() {
        let defaults = makeDefaults()
        defaults.set("mystery-theme", forKey: "home.selectedTheme")
        defaults.set(3, forKey: "home.themeStyleVersion")

        let store = makeStore(defaults: defaults)

        #expect(store.selectedTheme == .green)
        #expect(defaults.string(forKey: "home.selectedTheme") == "mystery-theme")
        #expect(defaults.integer(forKey: "home.themeStyleVersion") == 3)
    }

    @Test
    @MainActor
    func greenPresetPaletteUsesDarkBrandRoles() {
        let palette = HomeWindowStore.ThemePreset.green.palette

        #expect(palette.isDark)
        assertColor(palette.accent, equalsHex: "#00F7A2")
        assertColor(palette.textPrimary, equalsHex: "#FFFFFF")
        assertColor(palette.canvasTop, equalsHex: "#000000")
    }
}

@MainActor
private func makeStore(defaults: UserDefaults) -> HomeWindowStore {
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
    return HomeWindowStore(coordinator: coordinator, defaults: defaults)
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "HomeWindowStoreThemeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func assertColor(_ color: Color, equalsHex hex: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let expected = hexRGBComponents(hex)
    let resolved = NSColor(color).usingColorSpace(.deviceRGB)

    #expect(resolved != nil, sourceLocation: sourceLocation)
    guard let resolved else {
        return
    }

    let actual = (
        red: resolved.redComponent,
        green: resolved.greenComponent,
        blue: resolved.blueComponent
    )

    #expect(abs(actual.red - expected.red) < 0.01, sourceLocation: sourceLocation)
    #expect(abs(actual.green - expected.green) < 0.01, sourceLocation: sourceLocation)
    #expect(abs(actual.blue - expected.blue) < 0.01, sourceLocation: sourceLocation)
}

private func hexRGBComponents(_ hex: String) -> (red: Double, green: Double, blue: Double) {
    let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    precondition(sanitized.count == 6, "Expected #RRGGBB hex color")

    let scanner = Scanner(string: sanitized)
    var value: UInt64 = 0
    scanner.scanHexInt64(&value)

    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return (red, green, blue)
}
