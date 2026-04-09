import CoreGraphics
import Testing
@testable import SpeechBarInfrastructure

@Suite("TranscriptInjectionTargetResolver")
struct TranscriptInjectionTargetResolverTests {
    @Test
    func prefersFocusedElementCenterWhenAvailable() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 180, y: 160, width: 820, height: 520)
        let element = CGRect(x: 260, y: 260, width: 360, height: 44)

        let resolved = TranscriptInjectionTargetResolver.resolve(
            elementFrame: element,
            windowFrame: window,
            screenFrames: [screen]
        )

        #expect(resolved?.screenFrame == screen)
        #expect(resolved?.destinationPoint == CGPoint(x: 440, y: 282))
    }

    @Test
    func fallsBackToWindowBiasedPointWhenElementFrameIsMissing() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let window = CGRect(x: 140, y: 110, width: 900, height: 640)

        let resolved = TranscriptInjectionTargetResolver.resolve(
            elementFrame: nil,
            windowFrame: window,
            screenFrames: [screen]
        )

        #expect(resolved?.screenFrame == screen)
        #expect(resolved?.destinationPoint == CGPoint(x: 590, y: 545.2))
    }

    @Test
    func returnsNilWhenNoScreenMatchesTheTargetFrames() {
        let resolved = TranscriptInjectionTargetResolver.resolve(
            elementFrame: CGRect(x: 2100, y: 800, width: 240, height: 40),
            windowFrame: CGRect(x: 2000, y: 700, width: 600, height: 500),
            screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        )

        #expect(resolved == nil)
    }
}
