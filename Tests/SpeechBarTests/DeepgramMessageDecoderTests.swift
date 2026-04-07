import Testing
import SpeechBarDomain
@testable import SpeechBarInfrastructure

@Suite("DeepgramMessageDecoder")
struct DeepgramMessageDecoderTests {
    @Test
    func decodeInterimResultsMessage() throws {
        let decoder = DeepgramMessageDecoder()
        let payload = """
        {
          "type": "Results",
          "channel": {
            "alternatives": [
              { "transcript": "hello world" }
            ]
          },
          "is_final": false
        }
        """.data(using: .utf8)!

        let events = try decoder.decode(data: payload)
        #expect(events == [.interim("hello world")])
    }

    @Test
    func decodeFinalResultsMessage() throws {
        let decoder = DeepgramMessageDecoder()
        let payload = """
        {
          "type": "Results",
          "channel": {
            "alternatives": [
              { "transcript": "final transcript" }
            ]
          },
          "is_final": true
        }
        """.data(using: .utf8)!

        let events = try decoder.decode(data: payload)
        #expect(events == [.final("final transcript")])
    }

    @Test
    func decodeSpeechStartedMessage() throws {
        let decoder = DeepgramMessageDecoder()
        let payload = """
        {
          "type": "SpeechStarted",
          "timestamp": 0.8
        }
        """.data(using: .utf8)!

        let events = try decoder.decode(data: payload)
        #expect(events == [.speechStarted])
    }

    @Test
    func decodeUtteranceEndMessage() throws {
        let decoder = DeepgramMessageDecoder()
        let payload = """
        {
          "type": "UtteranceEnd",
          "last_word_end": 1.2
        }
        """.data(using: .utf8)!

        let events = try decoder.decode(data: payload)
        #expect(events == [.utteranceEnded])
    }

    @Test
    func decodeMetadataMessage() throws {
        let decoder = DeepgramMessageDecoder()
        let payload = """
        {
          "type": "Metadata",
          "request_id": "request-123"
        }
        """.data(using: .utf8)!

        let events = try decoder.decode(data: payload)
        #expect(events == [.metadata(requestID: "request-123")])
    }
}
