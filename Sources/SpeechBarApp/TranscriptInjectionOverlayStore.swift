import Combine
import Foundation
import SpeechBarDomain

@MainActor
final class TranscriptInjectionOverlayStore: ObservableObject, @unchecked Sendable {
    struct Presentation: Equatable {
        let publishID: UUID
        let target: TranscriptInjectionTargetSnapshot
        let startedAt: Date
        var endingStyle: TranscriptInjectionOverlayEndingStyle
    }

    @Published private(set) var presentation: Presentation?

    var activePublishID: UUID? {
        presentation?.publishID
    }

    func start(
        publishID: UUID,
        target: TranscriptInjectionTargetSnapshot,
        startedAt: Date
    ) {
        presentation = Presentation(
            publishID: publishID,
            target: target,
            startedAt: startedAt,
            endingStyle: .success
        )
    }

    func complete(
        publishID: UUID,
        outcome: TranscriptDeliveryOutcome
    ) {
        guard var presentation, presentation.publishID == publishID else {
            return
        }

        switch outcome {
        case .copiedToClipboard:
            presentation.endingStyle = .downgraded
            self.presentation = presentation

        case .insertedIntoFocusedApp, .typedIntoFocusedApp, .pasteShortcutSent:
            presentation.endingStyle = .success
            self.presentation = presentation

        case .publishedOnly:
            clear(publishID: publishID)
        }
    }

    func clear(publishID: UUID? = nil) {
        guard let publishID else {
            presentation = nil
            return
        }

        guard presentation?.publishID == publishID else {
            return
        }

        presentation = nil
    }
}
