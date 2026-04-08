import AppKit
import SwiftUI
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationTheme")
struct MemoryConstellationThemeTests {
    @Test
    func greenPaletteBuildsDefaultConstellationTheme() {
        let theme = MemoryConstellationVisualTheme(palette: HomeWindowStore.ThemePreset.green.palette)

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
