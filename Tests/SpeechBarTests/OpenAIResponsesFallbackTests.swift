import Foundation
import Testing
import SpeechBarDomain
import SpeechBarInfrastructure

@Suite("OpenAIResponsesFallback")
struct OpenAIResponsesFallbackTests {
    @Test
    func responses404FallsBackToChatCompletionsForResearchAndPolish() async throws {
        let endpoint = URL(string: "https://hnd1.aihub.zeabur.ai/v1/responses")!
        let configuration = OpenAIResponsesRequestConfiguration(
            endpoint: endpoint,
            model: "gpt-4.1-mini",
            timeoutInterval: 5
        )
        let provider = StaticResponsesConfigurationProvider(configuration: configuration)
        let session = makeStubSession()

        StubOpenAIURLProtocol.reset(
            stubs: [
                StubbedHTTPResponse(
                    statusCode: 404,
                    body: #"{"error":{"message":"Resource not found"}}"#
                ),
                StubbedHTTPResponse(
                    statusCode: 200,
                    body: #"{"choices":[{"message":{"role":"assistant","content":"{\"terms\":[\"OpenAI API\",\"Demo Day\"]}"}}]}"#
                ),
                StubbedHTTPResponse(
                    statusCode: 404,
                    body: #"{"error":{"message":"Resource not found"}}"#
                ),
                StubbedHTTPResponse(
                    statusCode: 200,
                    body: #"{"choices":[{"message":{"role":"assistant","content":"OpenAI API Demo Day"}}]}"#
                )
            ]
        )

        let researchClient = OpenAIResponsesResearchClient(
            session: session,
            credentialProvider: MockCredentialProvider(storedAPIKey: "test-key"),
            configurationProvider: provider
        )
        let glossary = try await researchClient.generateTerminology(
            profession: "AI 创业者",
            memoryProfile: "常用 OpenAI API 和 Demo Day"
        )

        let postProcessor = OpenAIResponsesTranscriptPostProcessor(
            session: session,
            credentialProvider: MockCredentialProvider(storedAPIKey: "test-key"),
            configurationProvider: provider
        )
        let polished = try await postProcessor.polish(
            transcript: "openai api demo day",
            context: UserProfileContext(
                profession: "AI 创业者",
                memoryProfile: "",
                terminologyGlossary: [],
                isTerminologyGlossaryEnabled: true,
                polishMode: .light,
                skipShortPolish: false,
                shortPolishCharacterThreshold: 8,
                useClipboardContextForPolish: false,
                useFrontmostAppContextForPolish: false,
                polishTimeoutSeconds: 1.8
            )
        )

        #expect(glossary.map(\.term) == ["OpenAI API", "Demo Day"])
        #expect(polished == "OpenAI API Demo Day")

        let requests = StubOpenAIURLProtocol.capturedRequests()
        #expect(requests.count == 4)
        #expect(requests[0].url?.path == "/v1/responses")
        #expect(requests[1].url?.path == "/v1/chat/completions")
        #expect(requests[2].url?.path == "/v1/responses")
        #expect(requests[3].url?.path == "/v1/chat/completions")

        let researchFallbackBody = try requestBodyJSONObject(from: requests[1])
        let researchMessages = researchFallbackBody["messages"] as? [[String: String]]
        #expect(researchFallbackBody["tools"] == nil)
        #expect(researchMessages?.count == 2)
        #expect(researchFallbackBody["model"] as? String == "gpt-4.1-mini")

        let polishFallbackBody = try requestBodyJSONObject(from: requests[3])
        let polishMessages = polishFallbackBody["messages"] as? [[String: String]]
        #expect(polishMessages?.count == 2)
        #expect(polishFallbackBody["model"] as? String == "gpt-4.1-mini")
    }
}

private struct StaticResponsesConfigurationProvider: OpenAIResponsesConfigurationProviding {
    let configuration: OpenAIResponsesRequestConfiguration

    func researchConfiguration() async -> OpenAIResponsesRequestConfiguration {
        configuration
    }

    func polishConfiguration() async -> OpenAIResponsesRequestConfiguration {
        configuration
    }
}

private struct StubbedHTTPResponse {
    let statusCode: Int
    let body: String
}

private final class StubOpenAIURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queuedResponses: [StubbedHTTPResponse] = []
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let response = Self.dequeueResponse(for: request) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "StubOpenAIURLProtocol", code: 0))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(stubs: [StubbedHTTPResponse]) {
        lock.lock()
        queuedResponses = stubs
        recordedRequests = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    private static func dequeueResponse(for request: URLRequest) -> StubbedHTTPResponse? {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else { return nil }
        return queuedResponses.removeFirst()
    }
}

private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubOpenAIURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestBodyJSONObject(from request: URLRequest) throws -> [String: Any] {
    let body = try #require(requestBodyData(from: request))
    let object = try JSONSerialization.jsonObject(with: body)
    return try #require(object as? [String: Any])
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count < 0 {
            return nil
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}
