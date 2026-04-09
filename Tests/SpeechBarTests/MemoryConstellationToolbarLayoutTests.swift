import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationToolbarLayout")
struct MemoryConstellationToolbarLayoutTests {
    @Test
    func desktopWidthsUseOneFullRowPerToolbarGroup() {
        #expect(MemoryConstellationToolbarLayout.columnCount(for: 920, itemCount: 4) == 4)
        #expect(MemoryConstellationToolbarLayout.columnCount(for: 920, itemCount: 3) == 3)
    }

    @Test
    func narrowWidthsFallbackToTwoColumnsBeforeStacking() {
        #expect(MemoryConstellationToolbarLayout.columnCount(for: 520, itemCount: 4) == 2)
        #expect(MemoryConstellationToolbarLayout.columnCount(for: 320, itemCount: 4) == 1)
    }
}
