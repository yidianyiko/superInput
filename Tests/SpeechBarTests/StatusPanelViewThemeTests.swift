import Testing
@testable import SpeechBarApp

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
}
