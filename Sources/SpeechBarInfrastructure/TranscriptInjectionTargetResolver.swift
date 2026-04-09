import CoreGraphics

struct ResolvedTranscriptInjectionTargetGeometry: Equatable {
    let screenFrame: CGRect
    let destinationPoint: CGPoint
}

enum TranscriptInjectionTargetResolver {
    private static let screenInset: CGFloat = 56
    private static let windowVerticalBias: CGFloat = 0.68

    static func resolve(
        elementFrame: CGRect?,
        windowFrame: CGRect?,
        screenFrames: [CGRect]
    ) -> ResolvedTranscriptInjectionTargetGeometry? {
        let lookupPoint = elementFrame.map(center(of:)) ?? windowFrame.map(center(of:))
        guard let lookupPoint else {
            return nil
        }

        let screenFrame = screenFrames.first(where: { $0.contains(lookupPoint) })
            ?? windowFrame.flatMap { windowFrame in
                screenFrames.first(where: { $0.intersects(windowFrame) })
            }
        guard let screenFrame else {
            return nil
        }

        if let elementFrame {
            return ResolvedTranscriptInjectionTargetGeometry(
                screenFrame: screenFrame,
                destinationPoint: center(of: elementFrame)
            )
        }

        guard let windowFrame else {
            return nil
        }

        let insetScreenFrame = screenFrame.insetBy(dx: screenInset, dy: screenInset)
        let clampedMinX = min(insetScreenFrame.minX, insetScreenFrame.maxX)
        let clampedMaxX = max(insetScreenFrame.minX, insetScreenFrame.maxX)
        let clampedMinY = min(insetScreenFrame.minY, insetScreenFrame.maxY)
        let clampedMaxY = max(insetScreenFrame.minY, insetScreenFrame.maxY)
        let destinationPoint = CGPoint(
            x: min(max(windowFrame.midX, clampedMinX), clampedMaxX),
            y: min(max(windowFrame.minY + (windowFrame.height * windowVerticalBias), clampedMinY), clampedMaxY)
        )

        return ResolvedTranscriptInjectionTargetGeometry(
            screenFrame: screenFrame,
            destinationPoint: destinationPoint
        )
    }

    private static func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}
