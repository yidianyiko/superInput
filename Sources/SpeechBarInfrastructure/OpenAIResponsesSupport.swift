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

struct OpenAIChatCompletionRequestMessage: Sendable {
    let role: String
    let content: String
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

struct OpenAIChatCompletionsEnvelope: Decodable {
    let choices: [OpenAIChatCompletionsChoice]

    var outputText: String {
        choices
            .map(\.message.outputText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OpenAIChatCompletionsChoice: Decodable {
    let message: OpenAIChatCompletionsMessage
}

struct OpenAIChatCompletionsMessage: Decodable {
    let outputText: String

    private enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .content) {
            outputText = text
            return
        }

        if let parts = try? container.decode([OpenAIChatCompletionsContentPart].self, forKey: .content) {
            outputText = parts
                .compactMap(\.text)
                .joined()
            return
        }

        outputText = ""
    }
}

struct OpenAIChatCompletionsContentPart: Decodable {
    let text: String?
}

func performOpenAITextRequest(
    session: URLSession,
    configuration: OpenAIResponsesRequestConfiguration,
    apiKey: String,
    responsesBody: Data,
    chatMessages: [OpenAIChatCompletionRequestMessage],
    chatMaxTokens: Int
) async throws -> String {
    do {
        let data = try await performOpenAIJSONRequest(
            session: session,
            url: configuration.endpoint,
            apiKey: apiKey,
            timeoutInterval: configuration.timeoutInterval,
            body: responsesBody
        )
        return try decodeResponsesText(from: data)
    } catch OpenAIResponsesClientError.badHTTPStatus(let code, _) where code == 404 {
        let chatEndpoint = chatCompletionsEndpoint(fromResponsesEndpoint: configuration.endpoint)
        let chatBody = try JSONSerialization.data(
            withJSONObject: [
                "model": configuration.model,
                "messages": chatMessages.map { message in
                    [
                        "role": message.role,
                        "content": message.content
                    ]
                },
                "max_tokens": chatMaxTokens
            ]
        )
        let data = try await performOpenAIJSONRequest(
            session: session,
            url: chatEndpoint,
            apiKey: apiKey,
            timeoutInterval: configuration.timeoutInterval,
            body: chatBody
        )
        return try decodeChatCompletionsText(from: data)
    }
}

private func performOpenAIJSONRequest(
    session: URLSession,
    url: URL,
    apiKey: String,
    timeoutInterval: TimeInterval,
    body: Data
) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeoutInterval
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw OpenAIResponsesClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw OpenAIResponsesClientError.badHTTPStatus(httpResponse.statusCode, body)
    }

    return data
}

private func decodeResponsesText(from data: Data) throws -> String {
    let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
    let text = envelope.outputText
    guard !text.isEmpty else {
        throw OpenAIResponsesClientError.emptyOutput
    }
    return text
}

private func decodeChatCompletionsText(from data: Data) throws -> String {
    let envelope = try JSONDecoder().decode(OpenAIChatCompletionsEnvelope.self, from: data)
    let text = envelope.outputText
    guard !text.isEmpty else {
        throw OpenAIResponsesClientError.emptyOutput
    }
    return text
}

private func chatCompletionsEndpoint(fromResponsesEndpoint endpoint: URL) -> URL {
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
        return endpoint.deletingLastPathComponent().appendingPathComponent("chat/completions")
    }

    let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.hasSuffix("/chat/completions") {
        return endpoint
    }

    if path.hasSuffix("/responses") {
        components.path = String(path.dropLast("/responses".count)) + "/chat/completions"
        return components.url ?? endpoint
    }

    if path.hasSuffix("/v1") {
        components.path = path + "/chat/completions"
        return components.url ?? endpoint
    }

    if path.isEmpty || path == "/" {
        components.path = "/v1/chat/completions"
        return components.url ?? endpoint
    }

    components.path = path + "/chat/completions"
    return components.url ?? endpoint
}
