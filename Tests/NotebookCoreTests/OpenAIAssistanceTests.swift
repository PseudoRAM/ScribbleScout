import Foundation
import Testing
@testable import NotebookCore

@Suite("Assistance routing", .serialized)
struct OpenAIAssistanceTests {
    private func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func decision(_ route: String = "web_research", confidence: Double = 0.95) -> [String: Any] {
        ["answers": [["name": "assistance_route", "type": "choice", "choice": route, "confidence": confidence]]]
    }
    private func response(_ text: String, citations: [[String: Any]] = [], searched: Bool = false) -> [String: Any] {
        var output: [[String: Any]] = [["type": "message", "content": [["type": "output_text", "text": text, "annotations": citations]]]]
        if searched { output.insert(["type": "web_search_call", "status": "completed"], at: 0) }
        return ["status": "completed", "output": output]
    }

    @Test(arguments: AssistanceRoute.allCases)
    func parsesEveryRoute(route: AssistanceRoute) throws {
        #expect(try OpenAIAssistance.parseDecision(data(decision(route.rawValue))).route == route)
    }

    @Test func uncertainAndMalformedDecisionsDoNotStartResearch() throws {
        #expect(try OpenAIAssistance.parseDecision(data(decision(confidence: 0.74))).route == .clarify)
        for invalid in [decision("unknown"), decision(confidence: 2), ["answers": []]] {
            #expect(throws: AssistanceError.self) { try OpenAIAssistance.parseDecision(data(invalid)) }
        }
        let refusal = ["answers": [["name": "assistance_route", "type": "refusal"]]]
        #expect(throws: AssistanceError.refused) { try OpenAIAssistance.parseDecision(data(refusal)) }
    }

    @Test func toolsAndStorageAreEnforcedByRequestBodies() {
        let quick = OpenAIAssistance.answerBody("Explain an index", research: false)
        #expect(quick["tools"] == nil)
        #expect(quick["store"] as? Bool == false)
        let research = OpenAIAssistance.answerBody("Public question only", research: true)
        #expect(research["input"] as? String == "Public question only")
        #expect((research["tool_choice"] as? [String: String])?["type"] == "web_search")
        #expect(research["max_tool_calls"] as? Int == 3)
        #expect(research["store"] as? Bool == false)
        #expect(OpenAIAssistance.fallbackBody("route me")["tools"] == nil)
    }

    @Test func selectionImagesReachOnlyRoutingAndQuickAnswers() throws {
        let image = Data([1, 2, 3])
        for body in [OpenAIAssistance.decisionBody("Explain selection", image: image),
                     OpenAIAssistance.fallbackBody("Explain selection", image: image),
                     OpenAIAssistance.answerBody("Explain selection", research: false, image: image)] {
            let input = try #require(body["input"] as? [[String: Any]])
            let content = try #require(input.first?["content"] as? [[String: String]])
            #expect(content.first?["text"] == "Explain selection")
            #expect(content.last?["image_url"] == "data:image/png;base64,AQID")
        }
        let research = OpenAIAssistance.answerBody("Public question", research: true, image: image)
        #expect(research["input"] as? String == "Public question")
        #expect(OpenAIAssistance.answerBody("Typed question", research: false)["input"] as? String == "Typed question")
    }

    @Test func researchRequiresCompletedSearchAndRealSourceMetadata() throws {
        let citation: [String: Any] = ["type": "url_citation", "url": "https://example.com/docs", "title": "Docs"]
        #expect(throws: AssistanceError.missingEvidence) {
            try OpenAIAssistance.parseAnswer(data(response("Unverified prose")), research: true)
        }
        #expect(throws: AssistanceError.missingEvidence) {
            try OpenAIAssistance.parseAnswer(data(response("No search", citations: [citation])), research: true)
        }
        let answer = try OpenAIAssistance.parseAnswer(data(response("Sourced answer", citations: [citation, citation], searched: true)), research: true)
        #expect(answer.citations.count == 1)
        let unsafe = ["type": "url_citation", "url": "javascript:alert(1)", "title": "Bad link"]
        #expect(throws: AssistanceError.missingEvidence) {
            try OpenAIAssistance.parseAnswer(data(response("Unsafe", citations: [unsafe], searched: true)), research: true)
        }
        #expect(try OpenAIAssistance.parseAnswer(data(response("Quick explanation")), research: false).text == "Quick explanation")
        #expect(throws: AssistanceError.incomplete) {
            try OpenAIAssistance.parseAnswer(data(["status": "incomplete", "output": []]), research: false)
        }
    }

    @Test func inlineSourceLinksPreserveUnicodeAndSurroundingText() throws {
        let citation: [String: Any] = ["type": "url_citation", "url": "https://example.com/docs", "title": "Docs",
                                       "start_index": 4, "end_index": 10]
        let value = try OpenAIAssistance.parseAnswer(data(response("📝 A [cite] end", citations: [citation], searched: true)), research: true)
        #expect(value.text == "📝 A [Docs](<https://example.com/docs>) end")
    }

    @Test func unsupportedDecisionsFallsBackButBadCredentialsDoNot() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOpenAI.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let provider = OpenAIAssistance(apiKey: "synthetic-test-key", session: session)
        StubOpenAI.handler = { request in
            #expect(request.url?.host == "api.openai.com")
            #expect(request.value(forHTTPHeaderField: "X-Client-Request-Id") != nil)
            if request.url?.path == "/v1/decisions" { return (404, Data()) }
            #expect(request.url?.path == "/v1/responses")
            return (200, try data(response("{\"route\":\"quick_response\"}")))
        }
        let result = try await provider.route("Explain a database index")
        #expect(result.route == .quickResponse)
        #expect(result.usedFallback)
        StubOpenAI.handler = { request in
            #expect(request.url?.path == "/v1/decisions")
            return (401, Data())
        }
        await #expect(throws: AssistanceError.api(401)) { try await provider.route("Explain an index") }
        await #expect(throws: AssistanceError.invalidInput) { try await provider.route("   ") }
        await #expect(throws: AssistanceError.invalidInput) { try await provider.route(String(repeating: "x", count: 8001)) }
    }
}

private final class StubOpenAI: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
