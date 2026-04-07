import Foundation
import SpeechBarDomain

public struct DeepgramMessageDecoder: Sendable {
    public init() {}

    public func decode(data: Data) throws -> [TranscriptEvent] {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)

        switch envelope.type {
        case "Results":
            let transcript = envelope.channel?.alternatives.first?.transcript?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !transcript.isEmpty else { return [] }
            if envelope.isFinal == true {
                return [.final(transcript)]
            }
            return [.interim(transcript)]

        case "SpeechStarted":
            return [.speechStarted]

        case "UtteranceEnd":
            return [.utteranceEnded]

        case "Metadata":
            return [.metadata(requestID: envelope.requestID)]

        case nil:
            return []

        default:
            return []
        }
    }
}

private struct Envelope: Decodable {
    let type: String?
    let channel: Channel?
    let isFinal: Bool?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case requestID = "request_id"
    }
}

private struct Channel: Decodable {
    let alternatives: [Alternative]
}

private struct Alternative: Decodable {
    let transcript: String?
}
