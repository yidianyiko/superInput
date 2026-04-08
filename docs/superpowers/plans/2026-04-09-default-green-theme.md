# Default Green Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new default green theme preset built around `#00F7A2`, `#000000`, and `#FFFFFF`, and apply it consistently across the home window, status panel, and Memory Constellation without removing the existing multi-theme picker.

**Architecture:** Expand `HomeWindowStore.HomeThemePalette` so the selected preset carries dark-aware text, control, and surface roles instead of leaving home/status views to hardcode light glass colors. Then move Memory Constellation off its global static blue/gold palette by injecting a palette-derived visual theme through SwiftUI environment values, so the constellation subtree reads from the same selected preset as the rest of the app.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit-backed hosting view smoke tests, Swift Testing (`import Testing`), existing `SpeechBarApp` / `SpeechBarTests` targets.

---

## File Structure

### New Files

- `Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift`
  - Covers default theme selection, migration behavior, and the new green preset’s palette roles.
- `Tests/SpeechBarTests/MemoryConstellationThemeTests.swift`
  - Covers conversion from `HomeThemePalette` into the shared Memory Constellation theme.

### Existing Files To Modify

- `Sources/SpeechBarApp/HomeWindowStore.swift`
  - Add the new green preset, expand `HomeThemePalette` with text/control roles, add palette variants for metric/form/empty states, and replace the old default-theme migration logic.
- `Sources/SpeechBarApp/SlashVibeVisualSystem.swift`
  - Move canvas, surface, hero-surface, and secondary button styling onto the new palette roles.
- `Sources/SpeechBarApp/HomeWindowView.swift`
  - Replace remaining light-only text and surface hardcodes with palette-driven values and helper variants.
- `Sources/SpeechBarApp/StatusPanelView.swift`
  - Update theme fallback to the new preset and replace white card/chip/input/button surfaces with palette-driven values.
- `Sources/SpeechBarApp/MemoryConstellationTheme.swift`
  - Replace the global static theme constants with a palette-derived value type plus SwiftUI environment plumbing.
- `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
  - Inject the selected home palette into the constellation subtree.
- `Sources/SpeechBarApp/MemoryConstellationHeaderView.swift`
  - Read text, pills, and picker tint from the injected constellation theme.
- `Sources/SpeechBarApp/MemoryConstellationToolbarView.swift`
  - Read chip and section text styling from the injected constellation theme.
- `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
  - Read canvas background, glows, bridge colors, and focus strokes from the injected constellation theme.
- `Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift`
  - Replace white overlays and gold focus copy with the injected constellation theme.
- `Sources/SpeechBarApp/MemoryTimelineRibbonView.swift`
  - Replace the old gold/white selection styling with the injected constellation theme.
- `Sources/SpeechBarApp/MemoryProfileSettingsSection.swift`
  - Move the disclosure card and header styling onto the injected constellation theme.
- `Sources/SpeechBarApp/OffscreenHomeSnapshot.swift`
  - Add the new preset to snapshot CLI parsing and mapping.
- `Tests/SpeechBarTests/HomeWindowViewTests.swift`
  - Add a render smoke test for the new default theme.
- `Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift`
  - Pass the selected palette into `MemoryConstellationScreen` so the smoke test covers the new theme injection path.

## Task 1: Add the Green Preset, Palette Roles, and Default Migration

**Files:**
- Create: `Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowStore.swift`
- Modify: `Sources/SpeechBarApp/StatusPanelView.swift`
- Modify: `Sources/SpeechBarApp/OffscreenHomeSnapshot.swift`

- [ ] **Step 1: Write the failing theme-store tests**

```swift
// Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift
import AppKit
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
    func freshInstallUsesVoltAsDefaultTheme() {
        let defaults = makeThemeDefaults()
        let store = HomeWindowStore(coordinator: makeThemeCoordinator(), defaults: defaults)

        #expect(store.selectedTheme == .volt)
        #expect(defaults.string(forKey: "home.selectedTheme") == HomeWindowStore.ThemePreset.volt.rawValue)
        #expect(defaults.integer(forKey: "home.themeStyleVersion") == 3)
    }

    @Test
    @MainActor
    func legacyAppleThemeMigratesToVolt() {
        let defaults = makeThemeDefaults()
        defaults.set(HomeWindowStore.ThemePreset.apple.rawValue, forKey: "home.selectedTheme")
        defaults.set(2, forKey: "home.themeStyleVersion")

        let store = HomeWindowStore(coordinator: makeThemeCoordinator(), defaults: defaults)

        #expect(store.selectedTheme == .volt)
    }

    @Test
    @MainActor
    func legacyNonDefaultThemeRemainsSelected() {
        let defaults = makeThemeDefaults()
        defaults.set(HomeWindowStore.ThemePreset.sunrise.rawValue, forKey: "home.selectedTheme")
        defaults.set(2, forKey: "home.themeStyleVersion")

        let store = HomeWindowStore(coordinator: makeThemeCoordinator(), defaults: defaults)

        #expect(store.selectedTheme == .sunrise)
    }

    @Test
    func voltPaletteUsesDarkBrandRoles() {
        let palette = HomeWindowStore.ThemePreset.volt.palette

        #expect(palette.isDark)
        #expect(hexString(for: palette.accent) == "#00F7A2")
        #expect(hexString(for: palette.textPrimary) == "#FFFFFF")
        #expect(hexString(for: palette.canvasTop) == "#000000")
    }
}

@MainActor
private func makeThemeCoordinator() -> VoiceSessionCoordinator {
    VoiceSessionCoordinator(
        hardwareSource: MockHardwareEventSource(),
        audioInputSource: MockAudioInputSource(),
        transcriptionClient: MockTranscriptionClient(),
        credentialProvider: MockCredentialProvider(storedAPIKey: "test-key"),
        transcriptPublisher: MockTranscriptPublisher(),
        sleepClock: ImmediateSleepClock()
    )
}

private func makeThemeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "HomeWindowStoreThemeTests.\(UUID().uuidString)")!
}

private func hexString(for color: Color) -> String {
    let resolved = NSColor(color).usingColorSpace(.deviceRGB)!
    let red = Int((resolved.redComponent * 255).rounded())
    let green = Int((resolved.greenComponent * 255).rounded())
    let blue = Int((resolved.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}
```

- [ ] **Step 2: Run the theme-store test target and verify it fails**

Run: `swift test --filter HomeWindowStoreThemeTests`

Expected: FAIL with compile errors such as `type 'HomeWindowStore.ThemePreset' has no member 'volt'`, `value of type 'HomeThemePalette' has no member 'textPrimary'`, and version expectations that still resolve to the old Apple preset.

- [ ] **Step 3: Implement the new preset, palette roles, and migration**

```swift
// Sources/SpeechBarApp/HomeWindowStore.swift
@MainActor
final class HomeWindowStore: ObservableObject {
    enum ThemePreset: String, CaseIterable, Codable, Identifiable {
        case volt
        case apple
        case sunrise
        case ocean
        case forest
        case graphite

        static let defaultPreset: Self = .volt
        static let legacyDefaultPreset: Self = .apple

        var id: String { rawValue }

        var title: String {
            switch self {
            case .volt:
                return "霓光绿"
            case .apple:
                return "Apple"
            case .sunrise:
                return "日光橙"
            case .ocean:
                return "海盐蓝"
            case .forest:
                return "苔原绿"
            case .graphite:
                return "石墨灰"
            }
        }

        var subtitle: String {
            switch self {
            case .volt:
                return "黑底、荧光绿强调与暗绿层次"
            case .apple:
                return "浅灰画布、黑白层级与单一蓝色强调"
            case .sunrise:
                return "更接近效率工具的暖色桌面感"
            case .ocean:
                return "偏冷静、专业的工作流风格"
            case .forest:
                return "更柔和，适合长时间使用"
            case .graphite:
                return "更克制，接近深色工业设计"
            }
        }

        var palette: HomeThemePalette {
            switch self {
            case .volt:
                return HomeThemePalette(
                    accent: Color(red: 0.00, green: 0.9686, blue: 0.6353),
                    accentSecondary: Color(red: 0.00, green: 0.82, blue: 0.56),
                    highlight: Color.white,
                    textPrimary: Color.white,
                    textSecondary: Color.white.opacity(0.76),
                    textMuted: Color.white.opacity(0.56),
                    sidebarTop: Color.black,
                    sidebarBottom: Color(red: 0.015, green: 0.04, blue: 0.03),
                    canvasTop: Color.black,
                    canvasBottom: Color(red: 0.02, green: 0.06, blue: 0.045),
                    cardTop: Color(red: 0.03, green: 0.10, blue: 0.075),
                    cardBottom: Color(red: 0.015, green: 0.055, blue: 0.04),
                    elevatedFill: Color(red: 0.05, green: 0.14, blue: 0.105),
                    border: Color(red: 0.18, green: 0.44, blue: 0.34),
                    softFill: Color(red: 0.04, green: 0.12, blue: 0.09),
                    controlFill: Color(red: 0.04, green: 0.12, blue: 0.09),
                    controlStroke: Color(red: 0.13, green: 0.32, blue: 0.25),
                    controlText: Color.white,
                    isDark: true
                )
            case .apple:
                return HomeThemePalette(
                    accent: Color(red: 0.00, green: 0.44, blue: 0.89),
                    accentSecondary: Color(red: 0.00, green: 0.40, blue: 0.80),
                    highlight: Color(red: 0.11, green: 0.11, blue: 0.12),
                    textPrimary: Color(red: 0.11, green: 0.11, blue: 0.12),
                    textSecondary: Color.black.opacity(0.58),
                    textMuted: Color.black.opacity(0.46),
                    sidebarTop: Color.white.opacity(0.96),
                    sidebarBottom: Color(red: 0.97, green: 0.97, blue: 0.98),
                    canvasTop: Color(red: 0.96, green: 0.96, blue: 0.97),
                    canvasBottom: Color(red: 0.95, green: 0.95, blue: 0.96),
                    cardTop: Color.white.opacity(0.98),
                    cardBottom: Color.white.opacity(0.94),
                    elevatedFill: Color.white.opacity(0.88),
                    border: Color.black.opacity(0.08),
                    softFill: Color.black.opacity(0.035),
                    controlFill: Color.white.opacity(0.92),
                    controlStroke: Color.black.opacity(0.08),
                    controlText: Color(red: 0.11, green: 0.11, blue: 0.12),
                    isDark: false
                )
            case .sunrise:
                return HomeThemePalette(
                    accent: Color(red: 0.92, green: 0.47, blue: 0.24),
                    accentSecondary: Color(red: 0.98, green: 0.76, blue: 0.41),
                    highlight: Color(red: 0.96, green: 0.59, blue: 0.34),
                    textPrimary: Color(red: 0.16, green: 0.13, blue: 0.11),
                    textSecondary: Color(red: 0.25, green: 0.20, blue: 0.16).opacity(0.76),
                    textMuted: Color(red: 0.25, green: 0.20, blue: 0.16).opacity(0.56),
                    sidebarTop: Color(red: 0.98, green: 0.95, blue: 0.92),
                    sidebarBottom: Color(red: 0.95, green: 0.89, blue: 0.85),
                    canvasTop: Color(red: 0.99, green: 0.98, blue: 0.96),
                    canvasBottom: Color(red: 0.96, green: 0.93, blue: 0.90),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.99, green: 0.96, blue: 0.93),
                    elevatedFill: Color(red: 0.98, green: 0.94, blue: 0.90),
                    border: Color(red: 0.90, green: 0.84, blue: 0.79),
                    softFill: Color(red: 0.98, green: 0.93, blue: 0.88),
                    controlFill: Color.white.opacity(0.94),
                    controlStroke: Color(red: 0.90, green: 0.84, blue: 0.79),
                    controlText: Color(red: 0.16, green: 0.13, blue: 0.11),
                    isDark: false
                )
            case .ocean:
                return HomeThemePalette(
                    accent: Color(red: 0.17, green: 0.47, blue: 0.78),
                    accentSecondary: Color(red: 0.27, green: 0.77, blue: 0.86),
                    highlight: Color(red: 0.21, green: 0.62, blue: 0.86),
                    textPrimary: Color(red: 0.12, green: 0.15, blue: 0.19),
                    textSecondary: Color(red: 0.12, green: 0.15, blue: 0.19).opacity(0.76),
                    textMuted: Color(red: 0.12, green: 0.15, blue: 0.19).opacity(0.56),
                    sidebarTop: Color(red: 0.92, green: 0.96, blue: 0.99),
                    sidebarBottom: Color(red: 0.87, green: 0.92, blue: 0.97),
                    canvasTop: Color(red: 0.96, green: 0.98, blue: 1.00),
                    canvasBottom: Color(red: 0.91, green: 0.95, blue: 0.99),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.94, green: 0.98, blue: 1.00),
                    elevatedFill: Color(red: 0.92, green: 0.97, blue: 1.00),
                    border: Color(red: 0.80, green: 0.88, blue: 0.95),
                    softFill: Color(red: 0.90, green: 0.96, blue: 0.99),
                    controlFill: Color.white.opacity(0.94),
                    controlStroke: Color(red: 0.80, green: 0.88, blue: 0.95),
                    controlText: Color(red: 0.12, green: 0.15, blue: 0.19),
                    isDark: false
                )
            case .forest:
                return HomeThemePalette(
                    accent: Color(red: 0.25, green: 0.53, blue: 0.37),
                    accentSecondary: Color(red: 0.65, green: 0.78, blue: 0.45),
                    highlight: Color(red: 0.41, green: 0.66, blue: 0.44),
                    textPrimary: Color(red: 0.13, green: 0.17, blue: 0.12),
                    textSecondary: Color(red: 0.13, green: 0.17, blue: 0.12).opacity(0.76),
                    textMuted: Color(red: 0.13, green: 0.17, blue: 0.12).opacity(0.56),
                    sidebarTop: Color(red: 0.94, green: 0.97, blue: 0.93),
                    sidebarBottom: Color(red: 0.89, green: 0.93, blue: 0.87),
                    canvasTop: Color(red: 0.97, green: 0.99, blue: 0.95),
                    canvasBottom: Color(red: 0.92, green: 0.96, blue: 0.91),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.95, green: 0.98, blue: 0.93),
                    elevatedFill: Color(red: 0.93, green: 0.97, blue: 0.91),
                    border: Color(red: 0.82, green: 0.88, blue: 0.79),
                    softFill: Color(red: 0.92, green: 0.96, blue: 0.89),
                    controlFill: Color.white.opacity(0.94),
                    controlStroke: Color(red: 0.82, green: 0.88, blue: 0.79),
                    controlText: Color(red: 0.13, green: 0.17, blue: 0.12),
                    isDark: false
                )
            case .graphite:
                return HomeThemePalette(
                    accent: Color(red: 0.28, green: 0.34, blue: 0.48),
                    accentSecondary: Color(red: 0.73, green: 0.53, blue: 0.36),
                    highlight: Color(red: 0.39, green: 0.47, blue: 0.62),
                    textPrimary: Color(red: 0.15, green: 0.16, blue: 0.19),
                    textSecondary: Color(red: 0.15, green: 0.16, blue: 0.19).opacity(0.76),
                    textMuted: Color(red: 0.15, green: 0.16, blue: 0.19).opacity(0.56),
                    sidebarTop: Color(red: 0.92, green: 0.93, blue: 0.95),
                    sidebarBottom: Color(red: 0.86, green: 0.88, blue: 0.91),
                    canvasTop: Color(red: 0.96, green: 0.97, blue: 0.98),
                    canvasBottom: Color(red: 0.90, green: 0.92, blue: 0.95),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.95, green: 0.95, blue: 0.97),
                    elevatedFill: Color(red: 0.93, green: 0.94, blue: 0.96),
                    border: Color(red: 0.81, green: 0.83, blue: 0.87),
                    softFill: Color(red: 0.92, green: 0.93, blue: 0.95),
                    controlFill: Color.white.opacity(0.94),
                    controlStroke: Color(red: 0.81, green: 0.83, blue: 0.87),
                    controlText: Color(red: 0.15, green: 0.16, blue: 0.19),
                    isDark: false
                )
            }
        }
    }

    struct HomeThemePalette {
        let accent: Color
        let accentSecondary: Color
        let highlight: Color
        let textPrimary: Color
        let textSecondary: Color
        let textMuted: Color
        let sidebarTop: Color
        let sidebarBottom: Color
        let canvasTop: Color
        let canvasBottom: Color
        let cardTop: Color
        let cardBottom: Color
        let elevatedFill: Color
        let border: Color
        let softFill: Color
        let controlFill: Color
        let controlStroke: Color
        let controlText: Color
        let isDark: Bool
    }

    private static let currentThemeStyleVersion = 3

    init(
        coordinator: VoiceSessionCoordinator,
        defaults: UserDefaults = .standard
    ) {
        self.coordinator = coordinator
        self.defaults = defaults
        self.selectedSection = Self.loadSection(from: defaults)
        self.memoryProfile = Self.loadString(forKey: Keys.memoryProfile, from: defaults)
        self.selectedTheme = Self.resolveThemeSelection(from: defaults)
        self.modelConfiguration = Self.loadModelConfiguration(from: defaults)
        self.subscriptionPurchaseURL = Self.loadString(
            forKey: Keys.subscriptionPurchaseURL,
            from: defaults,
            fallback: "https://your-domain.com/pricing"
        )
        self.subscriptionManageURL = Self.loadString(
            forKey: Keys.subscriptionManageURL,
            from: defaults,
            fallback: "https://your-domain.com/account/billing"
        )
        self.history = Self.loadHistory(from: defaults)
        bindPersistence()
        bindCoordinator()
    }

    private static func resolveThemeSelection(from defaults: UserDefaults) -> ThemePreset {
        let storedTheme = defaults.string(forKey: Keys.selectedTheme).flatMap(ThemePreset.init(rawValue:))
        let storedVersion = defaults.integer(forKey: Keys.themeStyleVersion)

        if storedVersion < currentThemeStyleVersion {
            let migratedTheme = migrateThemeSelection(storedTheme)
            defaults.set(migratedTheme.rawValue, forKey: Keys.selectedTheme)
            defaults.set(currentThemeStyleVersion, forKey: Keys.themeStyleVersion)
            return migratedTheme
        }

        return storedTheme ?? ThemePreset.defaultPreset
    }

    private static func migrateThemeSelection(_ storedTheme: ThemePreset?) -> ThemePreset {
        switch storedTheme {
        case nil, .some(ThemePreset.legacyDefaultPreset):
            return .defaultPreset
        case let .some(theme):
            return theme
        }
    }

    private static func loadTheme(from defaults: UserDefaults) -> ThemePreset {
        defaults.string(forKey: Keys.selectedTheme)
            .flatMap(ThemePreset.init(rawValue:))
            ?? .defaultPreset
    }
}
```

```swift
// Sources/SpeechBarApp/StatusPanelView.swift
@AppStorage("home.selectedTheme") private var selectedThemeRaw = HomeWindowStore.ThemePreset.defaultPreset.rawValue

private var selectedTheme: HomeWindowStore.ThemePreset {
    HomeWindowStore.ThemePreset(rawValue: selectedThemeRaw) ?? .defaultPreset
}
```

```swift
// Sources/SpeechBarApp/OffscreenHomeSnapshot.swift
enum ThemeOverride: String, Sendable {
    case volt
    case apple
    case sunrise
    case ocean
    case forest
    case graphite
}

private static func mapTheme(from override: OffscreenHomeSnapshotCommand.ThemeOverride) -> HomeWindowStore.ThemePreset {
    switch override {
    case .volt:
        return .volt
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
```

- [ ] **Step 4: Run the theme-store tests again**

Run: `swift test --filter HomeWindowStoreThemeTests`

Expected: PASS, including the migration test and the brand-color assertions.

- [ ] **Step 5: Commit the preset and migration work**

```bash
git add Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift \
    Sources/SpeechBarApp/HomeWindowStore.swift \
    Sources/SpeechBarApp/StatusPanelView.swift \
    Sources/SpeechBarApp/OffscreenHomeSnapshot.swift
git commit -m "feat: add default green theme preset"
```

## Task 2: Replace Home/Status Hardcodes with Palette-Driven Surfaces

**Files:**
- Modify: `Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowStore.swift`
- Modify: `Sources/SpeechBarApp/SlashVibeVisualSystem.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowView.swift`
- Modify: `Sources/SpeechBarApp/StatusPanelView.swift`
- Modify: `Tests/SpeechBarTests/HomeWindowViewTests.swift`

- [ ] **Step 1: Extend the theme tests with dark-surface variant expectations**

```swift
// Add to Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift
@Test
func voltPaletteVariantsStayDark() {
    let palette = HomeWindowStore.ThemePreset.volt.palette
    let metricPalette = palette.metricSurface(tint: palette.accent)
    let formPalette = palette.formSurface

    #expect(metricPalette.isDark)
    #expect(formPalette.isDark)
    #expect(hexString(for: formPalette.cardTop) != "#FFFFFF")
    #expect(hexString(for: formPalette.controlText) == "#FFFFFF")
}
```

```swift
// Add to Tests/SpeechBarTests/HomeWindowViewTests.swift
@Test
@MainActor
func greenThemeRendersHomeWindowWithoutLayoutRegression() async throws {
    let dependencies = makeHomeWindowDependencies()
    dependencies.store.selectedTheme = .volt

    let view = HomeWindowView(
        coordinator: dependencies.coordinator,
        agentMonitorCoordinator: dependencies.agentMonitorCoordinator,
        embeddedDisplayCoordinator: dependencies.embeddedDisplayCoordinator,
        diagnosticsCoordinator: dependencies.diagnosticsCoordinator,
        store: dependencies.store,
        userProfileStore: dependencies.userProfileStore,
        audioInputSettingsStore: dependencies.audioInputSettingsStore,
        modelSettingsStore: dependencies.modelSettingsStore,
        polishPlaygroundStore: dependencies.polishPlaygroundStore,
        localWhisperModelStore: dependencies.localWhisperModelStore,
        senseVoiceModelStore: dependencies.senseVoiceModelStore,
        memoryConstellationStore: dependencies.memoryConstellationStore,
        memoryFeatureFlagStore: dependencies.memoryFeatureFlagStore,
        pushToTalkSource: dependencies.pushToTalkSource
    )
    let hostingView = NSHostingView(rootView: view.frame(width: 1240, height: 780))

    hostingView.layoutSubtreeIfNeeded()

    #expect(hostingView.fittingSize.width > 0)
    #expect(hostingView.fittingSize.height > 0)
}
```

- [ ] **Step 2: Run the targeted tests and verify they fail**

Run: `swift test --filter "HomeWindow(StoreThemeTests|ViewTests)"`

Expected: FAIL with compile errors such as `value of type 'HomeThemePalette' has no member 'metricSurface'` and `value of type 'HomeThemePalette' has no member 'formSurface'`.

- [ ] **Step 3: Add palette variants and switch home/status rendering to them**

```swift
// Sources/SpeechBarApp/HomeWindowStore.swift
extension HomeWindowStore.HomeThemePalette {
    var preferredColorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    func metricSurface(tint: Color) -> Self {
        .init(
            accent: tint,
            accentSecondary: tint.opacity(0.78),
            highlight: tint,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            sidebarTop: sidebarTop,
            sidebarBottom: sidebarBottom,
            canvasTop: canvasTop,
            canvasBottom: canvasBottom,
            cardTop: softFill.opacity(isDark ? 1.0 : 0.6),
            cardBottom: cardBottom,
            elevatedFill: elevatedFill,
            border: tint.opacity(isDark ? 0.28 : 0.20),
            softFill: tint.opacity(isDark ? 0.14 : 0.10),
            controlFill: controlFill,
            controlStroke: controlStroke,
            controlText: controlText,
            isDark: isDark
        )
    }

    var formSurface: Self {
        .init(
            accent: accent,
            accentSecondary: accentSecondary,
            highlight: highlight,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            sidebarTop: sidebarTop,
            sidebarBottom: sidebarBottom,
            canvasTop: canvasTop,
            canvasBottom: canvasBottom,
            cardTop: controlFill,
            cardBottom: controlFill,
            elevatedFill: elevatedFill,
            border: controlStroke,
            softFill: softFill,
            controlFill: controlFill,
            controlStroke: controlStroke,
            controlText: controlText,
            isDark: isDark
        )
    }
}
```

```swift
// Sources/SpeechBarApp/SlashVibeVisualSystem.swift
struct SlashVibeCanvas: View {
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.canvasTop, palette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    palette.isDark ? palette.softFill.opacity(0.55) : Color.white.opacity(0.88),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [palette.accent.opacity(palette.isDark ? 0.14 : 0.05), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 320
            )
            .ignoresSafeArea()
        }
    }
}

private struct SlashVibeHeroSurfaceModifier: ViewModifier {
    let palette: HomeWindowStore.HomeThemePalette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.elevatedFill, palette.cardBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.controlStroke, lineWidth: 1)
                    )
            )
    }
}

struct SlashVibeHeroSecondaryButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.controlStroke, lineWidth: 1)
            )
            .foregroundStyle(palette.controlText)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
    }
}
```

```swift
// Sources/SpeechBarApp/HomeWindowView.swift
.background(store.palette.canvasTop)
.environment(\.colorScheme, store.palette.preferredColorScheme)

Text("SlashVibe")
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .foregroundStyle(store.palette.textMuted)

Text("让语音输入像系统功能一样自然")
    .font(.system(size: 31, weight: .bold, design: .rounded))
    .foregroundStyle(store.palette.textPrimary)

Text("按右侧 Command 开始或结束录音。转写、润色与写入整合为一个更安静的工作流。")
    .font(.system(size: 14, weight: .medium))
    .foregroundStyle(store.palette.textSecondary)

Button("打开辅助功能设置") {
    AccessibilityPermissionManager.openSystemSettings()
}
.buttonStyle(SlashVibeHeroSecondaryButtonStyle(palette: store.palette))

MetricCard(
    title: "累计录音次数",
    value: "\(store.totalSessionCount)",
    detail: "总共完成的转写会话",
    symbol: "waveform.path.ecg.rectangle.fill",
    tint: store.palette.accent,
    palette: store.palette
)
```

```swift
// Sources/SpeechBarApp/HomeWindowView.swift helper replacements
private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .slashVibeSurface(palette: palette.metricSurface(tint: tint), cornerRadius: 20, accent: tint)
    }
}

private struct EmptyStateCard: View {
    let title: String
    let detail: String
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slashVibeSurface(palette: palette.formSurface, cornerRadius: 18)
    }
}

private struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.clear)
                .slashVibeSurface(palette: palette.formSurface, cornerRadius: 18)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }
        }
    }
}
```

```swift
// Sources/SpeechBarApp/StatusPanelView.swift
var body: some View {
    ZStack {
        SlashVibeCanvas(palette: palette)

        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                triggerCard
                monitorSummaryCard
                transcriptPreviewCard
                polishCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    .environment(\.colorScheme, palette.preferredColorScheme)
}

CompactStatusCard(
    title: "状态",
    value: sessionTitle,
    tint: sessionTint,
    palette: palette
)
CompactStatusCard(
    title: "输出",
    value: "当前输入框",
    tint: palette.highlight,
    palette: palette
)

Text("SlashVibe")
    .font(.system(size: 18, weight: .bold, design: .rounded))
    .foregroundStyle(palette.textPrimary)

Text("Voice input")
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .foregroundStyle(palette.textMuted)

private struct CompactStatusCard: View {
    let title: String
    let value: String
    let tint: Color
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.controlStroke, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 4: Run the targeted theme and home smoke tests**

Run: `swift test --filter "HomeWindow(StoreThemeTests|ViewTests)"`

Expected: PASS, including the new palette-variant expectations and the home-window smoke render under `.volt`.

- [ ] **Step 5: Commit the home/status surface rewrite**

```bash
git add Tests/SpeechBarTests/HomeWindowStoreThemeTests.swift \
    Tests/SpeechBarTests/HomeWindowViewTests.swift \
    Sources/SpeechBarApp/HomeWindowStore.swift \
    Sources/SpeechBarApp/SlashVibeVisualSystem.swift \
    Sources/SpeechBarApp/HomeWindowView.swift \
    Sources/SpeechBarApp/StatusPanelView.swift
git commit -m "refactor: use palette-driven home theme surfaces"
```

## Task 3: Inject the Selected Palette into Memory Constellation

**Files:**
- Create: `Tests/SpeechBarTests/MemoryConstellationThemeTests.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationTheme.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationScreen.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationHeaderView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationToolbarView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationCanvasView.swift`
- Modify: `Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift`
- Modify: `Sources/SpeechBarApp/MemoryTimelineRibbonView.swift`
- Modify: `Sources/SpeechBarApp/MemoryProfileSettingsSection.swift`
- Modify: `Sources/SpeechBarApp/HomeWindowView.swift`
- Modify: `Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift`

- [ ] **Step 1: Write the failing Memory Constellation theme tests**

```swift
// Tests/SpeechBarTests/MemoryConstellationThemeTests.swift
import AppKit
import SwiftUI
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationTheme")
struct MemoryConstellationThemeTests {
    @Test
    func voltPaletteBuildsGreenConstellationTheme() {
        let theme = MemoryConstellationVisualTheme(palette: HomeWindowStore.ThemePreset.volt.palette)

        #expect(hexString(for: theme.canvasColors[0]) == "#000000")
        #expect(hexString(for: theme.primaryText) == "#FFFFFF")
        #expect(hexString(for: theme.focusAccent) == "#00F7A2")
        #expect(hexString(for: theme.clusterColor(for: .vocabulary)) == "#00F7A2")
    }
}

private func hexString(for color: Color) -> String {
    let resolved = NSColor(color).usingColorSpace(.deviceRGB)!
    let red = Int((resolved.redComponent * 255).rounded())
    let green = Int((resolved.greenComponent * 255).rounded())
    let blue = Int((resolved.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}
```

```swift
// Modify Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift
let rootView = MemoryConstellationScreen(
    constellationStore: constellationStore,
    userProfileStore: userProfileStore,
    memoryFeatureFlagStore: featureFlags,
    palette: HomeWindowStore.ThemePreset.volt.palette,
    completedTranscript: nil
)
```

- [ ] **Step 2: Run the constellation theme tests and verify they fail**

Run: `swift test --filter "MemoryConstellation(ThemeTests|ScreenSmokeTests)"`

Expected: FAIL with compile errors such as `cannot find 'MemoryConstellationVisualTheme' in scope` and missing `palette:` arguments on `MemoryConstellationScreen`.

- [ ] **Step 3: Replace the static constellation palette with an injected theme**

```swift
// Sources/SpeechBarApp/MemoryConstellationTheme.swift
import SwiftUI

struct MemoryConstellationVisualTheme {
    let canvasColors: [Color]
    let panelFill: Color
    let elevatedFill: Color
    let panelStroke: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let focusAccent: Color
    let chipFill: Color
    let chipSelectedText: Color

    init(palette: HomeWindowStore.HomeThemePalette) {
        self.canvasColors = [
            palette.canvasTop,
            palette.canvasBottom,
            palette.softFill
        ]
        self.panelFill = palette.softFill.opacity(palette.isDark ? 0.94 : 0.82)
        self.elevatedFill = palette.elevatedFill
        self.panelStroke = palette.controlStroke
        self.primaryText = palette.textPrimary
        self.secondaryText = palette.textSecondary
        self.accent = palette.accent
        self.focusAccent = palette.accent
        self.chipFill = palette.controlFill
        self.chipSelectedText = palette.isDark ? Color.black.opacity(0.82) : Color.white
    }

    var canvasBackground: LinearGradient {
        LinearGradient(colors: canvasColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func clusterColor(for kind: MemoryConstellationClusterKind) -> Color {
        switch kind {
        case .vocabulary:
            return accent
        case .style:
            return accent.opacity(0.86)
        case .scenes:
            return Color.white.opacity(0.82)
        }
    }

    func clusterGlow(for kind: MemoryConstellationClusterKind, emphasis: Double) -> RadialGradient {
        let base = clusterColor(for: kind)
        let strength = max(0.24, min(0.72, emphasis))
        return RadialGradient(
            colors: [base.opacity(strength), base.opacity(strength * 0.34), .clear],
            center: .center,
            startRadius: 10,
            endRadius: 150
        )
    }
}

enum MemoryConstellationTheme {
    static func displayModeLabel(_ mode: MemoryConstellationDisplayMode) -> String {
        switch mode {
        case .full:
            return "完整显示"
        case .privacySafe:
            return "隐私保护"
        case .hidden:
            return "隐藏"
        }
    }
}

private struct MemoryConstellationThemeKey: EnvironmentKey {
    static let defaultValue = MemoryConstellationVisualTheme(palette: HomeWindowStore.ThemePreset.defaultPreset.palette)
}

extension EnvironmentValues {
    var memoryConstellationTheme: MemoryConstellationVisualTheme {
        get { self[MemoryConstellationThemeKey.self] }
        set { self[MemoryConstellationThemeKey.self] = newValue }
    }
}

struct MemoryConstellationPanel<Content: View>: View {
    @Environment(\.memoryConstellationTheme) private var theme
    let padding: CGFloat
    @ViewBuilder var content: Content

    init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(theme.panelFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(theme.panelStroke, lineWidth: 1)
            )
    }
}

struct MemoryConstellationTag: View {
    @Environment(\.memoryConstellationTheme) private var theme
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.chipFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(theme.panelStroke, lineWidth: 1)
            )
    }
}

struct MemoryConstellationChip: View {
    @Environment(\.memoryConstellationTheme) private var theme
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? theme.chipSelectedText : theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [theme.focusAccent, theme.accent.opacity(0.82)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(theme.chipFill)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? theme.focusAccent.opacity(0.82) : theme.panelStroke,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
```

```swift
// Sources/SpeechBarApp/MemoryConstellationScreen.swift
struct MemoryConstellationScreen: View {
    @ObservedObject var constellationStore: MemoryConstellationStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let palette: HomeWindowStore.HomeThemePalette
    let completedTranscript: PublishedTranscript?

    var body: some View {
        let theme = MemoryConstellationVisualTheme(palette: palette)

        VStack(alignment: .leading, spacing: 20) {
            MemoryConstellationHeaderView(
                snapshot: constellationStore.snapshot,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            ) {
                constellationStore.refreshPresentation()
            }

            MemoryConstellationToolbarView(
                selectedFilter: constellationStore.selectedFilter,
                selectedViewMode: constellationStore.selectedViewMode,
                selectFilter: constellationStore.selectFilter,
                selectViewMode: constellationStore.selectViewMode
            )

            MemoryConstellationCanvasView(
                snapshot: constellationStore.snapshot,
                focus: constellationStore.focus,
                selectedViewMode: constellationStore.selectedViewMode,
                capturePulseToken: constellationStore.capturePulseToken,
                hoverCluster: constellationStore.hoverCluster,
                focusBridge: constellationStore.focusBridge
            )

            MemoryConstellationRelationshipTrayView(
                cards: constellationStore.snapshot.relationshipCards,
                focusBridge: constellationStore.focusBridge
            )

            MemoryTimelineRibbonView(
                timeline: constellationStore.snapshot.timeline,
                selectedViewMode: constellationStore.selectedViewMode,
                selectedTimelineWindowID: constellationStore.selectedTimelineWindowID,
                selectViewMode: constellationStore.selectViewMode,
                selectTimelineWindow: constellationStore.selectTimelineWindow
            )

            MemoryProfileSettingsSection(
                userProfileStore: userProfileStore,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            )
        }
        .padding(24)
        .background(screenBackground(theme: theme))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(theme.panelStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
        .padding(2)
        .environment(\.memoryConstellationTheme, theme)
        .environment(\.colorScheme, palette.preferredColorScheme)
        .task {
            await constellationStore.reload()
        }
    }

    @ViewBuilder
    private func screenBackground(theme: MemoryConstellationVisualTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(theme.canvasBackground)

            RadialGradient(
                colors: [theme.clusterColor(for: .vocabulary).opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 320
            )

            RadialGradient(
                colors: [theme.clusterColor(for: .style).opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 300
            )
        }
    }
}
```

```swift
// Sources/SpeechBarApp/HomeWindowView.swift
MemoryConstellationScreen(
    constellationStore: memoryConstellationStore,
    userProfileStore: userProfileStore,
    memoryFeatureFlagStore: memoryFeatureFlagStore,
    palette: store.palette,
    completedTranscript: coordinator.lastCompletedTranscript
)
```

```swift
// Sources/SpeechBarApp/MemoryConstellationHeaderView.swift
@Environment(\.memoryConstellationTheme) private var theme

Text(snapshot.title)
    .font(.system(size: 34, weight: .semibold, design: .serif))
    .foregroundStyle(theme.primaryText)

.tint(theme.focusAccent)
```

```swift
// Sources/SpeechBarApp/MemoryConstellationToolbarView.swift
@Environment(\.memoryConstellationTheme) private var theme

Text(title)
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .tracking(1.2)
    .textCase(.uppercase)
    .foregroundStyle(theme.secondaryText)

Text(subtitle)
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(theme.secondaryText.opacity(0.88))
```

```swift
// Sources/SpeechBarApp/MemoryConstellationCanvasView.swift
@Environment(\.memoryConstellationTheme) private var theme

RoundedRectangle(cornerRadius: 28, style: .continuous)
    .fill(theme.canvasBackground)

.stroke(
    theme.focusAccent.opacity(0.32 * capturePulseProgress),
    lineWidth: 1 + (capturePulseProgress * 3)
)

LinearGradient(
    colors: [
        theme.accent.opacity(focused ? 0.95 : 0.45),
        theme.focusAccent.opacity(focused ? 0.88 : 0.38)
    ],
    startPoint: .leading,
    endPoint: .trailing
)
```

```swift
// Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift
@Environment(\.memoryConstellationTheme) private var theme

Text(card.title)
    .font(.system(size: 15, weight: .semibold, design: .rounded))
    .foregroundStyle(theme.primaryText)

Text(card.bridgeID == nil ? "返回总览" : "聚焦连接")
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .foregroundStyle(theme.focusAccent)
```

```swift
// Sources/SpeechBarApp/MemoryTimelineRibbonView.swift
@Environment(\.memoryConstellationTheme) private var theme

private func backgroundFill(for window: MemoryConstellationTimelineWindow) -> Color {
    window.id == selectedTimelineWindowID && selectedViewMode == .timelineReplay
        ? theme.accent.opacity(0.22)
        : theme.panelFill
}

private func borderColor(for window: MemoryConstellationTimelineWindow) -> Color {
    window.id == selectedTimelineWindowID && selectedViewMode == .timelineReplay
        ? theme.focusAccent.opacity(0.70)
        : theme.panelStroke
}
```

```swift
// Sources/SpeechBarApp/MemoryProfileSettingsSection.swift
@Environment(\.memoryConstellationTheme) private var theme

Text("辅助记忆控制")
    .font(.system(size: 18, weight: .semibold, design: .rounded))
    .foregroundStyle(theme.primaryText)

Text(isExpanded ? "收起" : "展开")
    .font(.system(size: 11, weight: .bold, design: .rounded))
    .foregroundStyle(theme.focusAccent)

.background(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(theme.panelFill)
)
.overlay(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(theme.panelStroke, lineWidth: 1)
)
```

- [ ] **Step 4: Run the constellation tests again**

Run: `swift test --filter "MemoryConstellation(ThemeTests|ScreenSmokeTests|AccessibilityTests)"`

Expected: PASS, including the new mapping test and the existing smoke/accessibility coverage.

- [ ] **Step 5: Commit the constellation retheme**

```bash
git add Tests/SpeechBarTests/MemoryConstellationThemeTests.swift \
    Tests/SpeechBarTests/MemoryConstellationScreenSmokeTests.swift \
    Sources/SpeechBarApp/MemoryConstellationTheme.swift \
    Sources/SpeechBarApp/MemoryConstellationScreen.swift \
    Sources/SpeechBarApp/MemoryConstellationHeaderView.swift \
    Sources/SpeechBarApp/MemoryConstellationToolbarView.swift \
    Sources/SpeechBarApp/MemoryConstellationCanvasView.swift \
    Sources/SpeechBarApp/MemoryConstellationRelationshipTrayView.swift \
    Sources/SpeechBarApp/MemoryTimelineRibbonView.swift \
    Sources/SpeechBarApp/MemoryProfileSettingsSection.swift \
    Sources/SpeechBarApp/HomeWindowView.swift
git commit -m "feat: theme memory constellation from selected palette"
```

## Task 4: Full Verification and Snapshot QA

**Files:**
- Modify: working tree only if verification exposes issues

- [ ] **Step 1: Run the focused SpeechBar theme tests**

Run:

```bash
swift test --filter HomeWindowStoreThemeTests
swift test --filter HomeWindowViewTests
swift test --filter MemoryConstellationThemeTests
swift test --filter MemoryConstellationScreenSmokeTests
swift test --filter MemoryConstellationAccessibilityTests
```

Expected: all PASS.

- [ ] **Step 2: Run the full test suite**

Run: `swift test`

Expected: PASS for the complete `SpeechBarTests` and `MemoryTests` suites.

- [ ] **Step 3: Generate offscreen snapshots for manual QA**

Run:

```bash
swift run SpeechBarApp --render-home-snapshot dist/offscreen-ui/home-volt.png --section home --theme volt
swift run SpeechBarApp --render-home-snapshot dist/offscreen-ui/settings-volt.png --section settings --theme volt
swift run SpeechBarApp --render-home-snapshot dist/offscreen-ui/memory-volt.png --section memory --theme volt
```

Expected: three PNG paths printed to stdout and matching files created under `dist/offscreen-ui/`.

- [ ] **Step 4: Review the visual checklist**

Check the generated snapshots and live app against this list:

- home canvas background reads black, not light gray
- hero, cards, chips, and secondary buttons use deep-green surfaces instead of white glass
- body text is white, supporting text is dimmed white, and primary emphasis is `#00F7A2`
- status panel uses the same dark palette for cards, badges, and form controls
- Memory Constellation no longer uses blue/gold/rose as its base palette
- semantic error and warning states still remain red/orange where they indicate system state

- [ ] **Step 5: Commit the verified rollout**

```bash
git add Sources/SpeechBarApp \
    Tests/SpeechBarTests \
    dist/offscreen-ui/home-volt.png \
    dist/offscreen-ui/settings-volt.png \
    dist/offscreen-ui/memory-volt.png
git commit -m "feat: roll out default green theme"
```

If snapshot artifacts should not stay in git for this repo, omit the PNGs from the commit and keep them as local QA output only.
