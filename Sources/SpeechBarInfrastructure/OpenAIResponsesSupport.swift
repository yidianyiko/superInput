import Foundation

public struct OpenAIResponsesRequestConfiguration: Sendable, Equatable {
    public let endpoint: URL
    public let model: String
    public let timeoutInterval: TimeInterval

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        model: String,
        timeoutInterval: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.model = model
        self.timeoutInterval = timeoutInterval
    }
}

public protocol OpenAIResponsesConfigurationProviding: Sendable {
    func researchConfiguration() async -> OpenAIResponsesRequestConfiguration
    func polishConfiguration() async -> OpenAIResponsesRequestConfiguration
}

enum OpenAIResponsesClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case badHTTPStatus(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing."
        case .invalidResponse:
            return "OpenAI returned an unexpected response."
        case .badHTTPStatus(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "OpenAI request failed with HTTP \(code)."
            }
            return "OpenAI request failed with HTTP \(code): \(trimmed)"
        case .emptyOutput:
            return "OpenAI returned no text output."
        }
    }
}

struct OpenAIResponsesEnvelope: Decodable {
    let output: [OpenAIResponsesOutputItem]

    var outputText: String {
        output
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OpenAIResponsesOutputItem: Decodable {
    let content: [OpenAIResponsesOutputContent]?
}

struct OpenAIResponsesOutputContent: Decodable {
    let text: String?
}
