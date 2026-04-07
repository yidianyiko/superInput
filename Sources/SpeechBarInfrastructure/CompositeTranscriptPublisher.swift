import Foundation
import SpeechBarDomain

public actor CompositeTranscriptPublisher: TranscriptPublisher {
    private let publishers: [any TranscriptPublisher]

    public init(publishers: [any TranscriptPublisher]) {
        self.publishers = publishers
    }

    public func publish(_ transcript: PublishedTranscript) async throws -> TranscriptDeliveryOutcome {
        var firstError: Error?
        var bestOutcome: TranscriptDeliveryOutcome?

        for publisher in publishers {
            do {
                let outcome = try await publisher.publish(transcript)
                bestOutcome = merge(bestOutcome, with: outcome)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let bestOutcome {
            return bestOutcome
        }

        if let firstError {
            throw firstError
        }

        return .publishedOnly
    }

    private func merge(
        _ current: TranscriptDeliveryOutcome?,
        with candidate: TranscriptDeliveryOutcome
    ) -> TranscriptDeliveryOutcome {
        guard let current else {
            return candidate
        }

        return rank(candidate) > rank(current) ? candidate : current
    }

    private func rank(_ outcome: TranscriptDeliveryOutcome) -> Int {
        switch outcome {
        case .insertedIntoFocusedApp:
            return 4
        case .typedIntoFocusedApp:
            return 3
        case .pasteShortcutSent:
            return 2
        case .copiedToClipboard:
            return 1
        case .publishedOnly:
            return 0
        }
    }
}
