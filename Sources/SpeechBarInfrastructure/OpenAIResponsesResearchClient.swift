import Foundation
import SpeechBarDomain

public actor OpenAIResponsesResearchClient: TerminologyResearchClient {
    private let session: URLSession
    private let credentialProvider: any CredentialProvider
    private let configurationProvider: any OpenAIResponsesConfigurationProviding

    public init(
        session: URLSession = .shared,
        credentialProvider: any CredentialProvider,
        configurationProvider: any OpenAIResponsesConfigurationProviding
    ) {
        self.session = session
        self.credentialProvider = credentialProvider
        self.configurationProvider = configurationProvider
    }

    public func generateTerminology(
        profession: String,
        memoryProfile: String
    ) async throws -> [TerminologyEntry] {
        let trimmedProfession = profession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfession.isEmpty else { return [] }

        let apiKey = try loadAPIKey()
        let configuration = await configurationProvider.researchConfiguration()

        let instructions = """
        你是一名术语研究助手。请为给定职业生成适合语音识别的领域术语词表。
        目标：
        1. 返回最常见、最可能在日常口语里被提到的术语、品牌、产品、职位、方法论、英文缩写
        2. 适合语音识别增强，优先短语，不要解释
        3. 中英混合可以
        4. 只返回 JSON，不要额外文字
        5. JSON 结构固定为 { "terms": ["...", "..."] }
        6. 尽量给出 100 个术语，避免重复
        """

        let prompt = """
        职业：\(trimmedProfession)

        用户补充背景：
        \(memoryProfile.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        let body: [String: Any] = [
            "model": configuration.model,
            "instructions": instructions,
            "input": prompt,
            "tools": [
                ["type": "web_search"]
            ],
            "max_output_tokens": 2_500
        ]

        let outputText = try await performRequest(
            configuration: configuration,
            apiKey: apiKey,
            body: body,
            fallbackMessages: [
                OpenAIChatCompletionRequestMessage(role: "system", content: instructions),
                OpenAIChatCompletionRequestMessage(role: "user", content: prompt)
            ],
            fallbackMaxTokens: 2_500
        )

        return parseTerminology(from: outputText)
    }

    private func performRequest(
        configuration: OpenAIResponsesRequestConfiguration,
        apiKey: String,
        body: [String: Any],
        fallbackMessages: [OpenAIChatCompletionRequestMessage],
        fallbackMaxTokens: Int
    ) async throws -> String {
        let requestBody = try JSONSerialization.data(withJSONObject: body)
        return try await performOpenAITextRequest(
            session: session,
            configuration: configuration,
            apiKey: apiKey,
            responsesBody: requestBody,
            chatMessages: fallbackMessages,
            chatMaxTokens: fallbackMaxTokens
        )
    }

    private func parseTerminology(from outputText: String) -> [TerminologyEntry] {
        let jsonText = extractJSONObject(from: outputText) ?? outputText

        struct Response: Decodable {
            let terms: [String]
        }

        var parsedTerms: [String] = []
        if let data = jsonText.data(using: .utf8),
           let response = try? JSONDecoder().decode(Response.self, from: data) {
            parsedTerms = response.terms
        } else if let data = jsonText.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) {
            parsedTerms = array
        }

        let normalized = normalizeTerms(parsedTerms)
        return normalized.map { TerminologyEntry(term: $0, isEnabled: true) }
    }

    private func normalizeTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for term in terms {
            let trimmed = term
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.count <= 48 else { continue }
            let signature = trimmed.lowercased()
            guard seen.insert(signature).inserted else { continue }
            result.append(trimmed)
            if result.count == 100 {
                break
            }
        }

        return result
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private func loadAPIKey() throws -> String {
        do {
            return try credentialProvider.loadAPIKey()
        } catch {
            throw OpenAIResponsesClientError.missingAPIKey
        }
    }
}
