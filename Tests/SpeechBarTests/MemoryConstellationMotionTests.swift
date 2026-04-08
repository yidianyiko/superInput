import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationMotion")
struct MemoryConstellationMotionTests {
    @Test
    func starOffsetsShiftAcrossPhasesWithinSmallDriftBounds() {
        let early = MemoryConstellationMotion.starOffset(
            cluster: .vocabulary,
            starIndex: 2,
            phase: 0
        )
        let later = MemoryConstellationMotion.starOffset(
            cluster: .vocabulary,
            starIndex: 2,
            phase: 2.4
        )

        #expect(abs(early.width - later.width) > 0.1 || abs(early.height - later.height) > 0.1)
        #expect(abs(early.width) <= 14)
        #expect(abs(early.height) <= 14)
        #expect(abs(later.width) <= 14)
        #expect(abs(later.height) <= 14)
    }
}
