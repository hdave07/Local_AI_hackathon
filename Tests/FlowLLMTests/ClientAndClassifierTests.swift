import FlowCore
@testable import FlowLLM
import Foundation
import Testing

@Suite("LMStudioConfiguration")
struct ConfigurationTests {
    @Test(arguments: ["http://localhost:1234/v1", "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1"])
    func acceptsLoopback(url: String) throws {
        _ = try LMStudioConfiguration(baseURL: URL(string: url)!)
    }

    @Test(arguments: ["https://api.openai.com/v1", "http://192.168.1.10:1234/v1", "file:///tmp/x", "http://localhost.evil.com/v1"])
    func rejectsNonLocal(url: String) {
        #expect(throws: ClassificationError.self) { try LMStudioConfiguration(baseURL: URL(string: url)!) }
    }

    @Test func rejectsEmptyModel() {
        #expect(throws: ClassificationError.self) { try LMStudioConfiguration(modelID: " ") }
    }
}

@Suite("LMStudioClient request and error mapping")
struct ClientTests {
    @Test func sendsSchemaConstrainedRequest() async throws {
        let transport = MockTransport([Fixtures.completion(Fixtures.intentJSON(action: "activate_app", target: "notes"))])
        let intent = try await capture { try await Fixtures.classifier(transport).classify("open notes") }.get()
        #expect(intent.action == .activateApp(.notes))

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "ternary-bonsai-2-2b-mlx")
        #expect(body["temperature"] as? Int == 0)
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schemaWrapper = try #require(format["json_schema"] as? [String: Any])
        #expect(schemaWrapper["strict"] as? Bool == true)
        let schema = try #require(schemaWrapper["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == "open notes")
    }

    @Test(arguments: [URLError.Code.cannotConnectToHost, .networkConnectionLost, .cannotFindHost])
    func serverUnavailable(code: URLError.Code) async {
        let result = await capture { try await Fixtures.classifier(MockTransport([.failure(code)])).classify("open notes") }
        guard case .failure(.serverUnavailable) = result else { Issue.record("got \(result)"); return }
    }

    @Test func timeout() async {
        let result = await capture { try await Fixtures.classifier(MockTransport([.failure(.timedOut)])).classify("open mail") }
        #expect(result == .failure(.timedOut))
    }

    @Test func httpErrorCarriesServerMessage() async {
        let transport = MockTransport([.http(status: 400, body: #"{"error":{"message":"No models loaded"}}"#)])
        let result = await capture { try await Fixtures.classifier(transport).classify("open mail") }
        #expect(result == .failure(.httpStatus(code: 400, message: "No models loaded")))
    }

    @Test func modelSubstitutionIsRejected() async {
        let transport = MockTransport([Fixtures.completion(Fixtures.intentJSON(action: "activate_app", target: "notes"), model: "other-model")])
        let result = await capture { try await Fixtures.classifier(transport).classify("open notes") }
        #expect(result == .failure(.modelMismatch(expected: Fixtures.model, actual: "other-model")))
    }

    @Test func truncatedOutputIsMalformed() async {
        let transport = MockTransport([
            Fixtures.completion(#"{"kind":"dir"#, finish: "length"),
            Fixtures.completion(#"{"kind":"dir"#, finish: "length"),
        ])
        let result = await capture { try await Fixtures.classifier(transport).classify("open notes") }
        #expect(result == .failure(.malformedJSON("output truncated at max_tokens")))
    }

    @Test func emptyContent() async {
        let transport = MockTransport([Fixtures.completion("  "), Fixtures.completion("")])
        let result = await capture { try await Fixtures.classifier(transport).classify("open notes") }
        #expect(result == .failure(.emptyResponse))
        #expect(transport.callCount == 2)
    }
}

@Suite("BonsaiIntentClassifier pipeline")
struct ClassifierTests {
    @Test func retriesOnceAfterMalformedJSON() async throws {
        let transport = MockTransport([
            Fixtures.completion("Sure, opening Notes!"),
            Fixtures.completion(Fixtures.intentJSON(action: "activate_app", target: "notes")),
        ])
        let intent = try await capture { try await Fixtures.classifier(transport).classify("open notes") }.get()
        #expect(intent.action == .activateApp(.notes))
        #expect(transport.callCount == 2)
    }

    @Test func givesUpAfterMaxAttempts() async {
        let transport = MockTransport([Fixtures.completion("nope"), Fixtures.completion("still nope"), Fixtures.completion("x")])
        let result = await capture { try await Fixtures.classifier(transport).classify("open notes") }
        guard case .failure(.malformedJSON) = result else { Issue.record("got \(result)"); return }
        #expect(transport.callCount == 2)
    }

    @Test func unsupportedActionIsNotRetried() async {
        let transport = MockTransport([Fixtures.completion(Fixtures.intentJSON(action: "open_app", target: "notes"))])
        let result = await capture { try await Fixtures.classifier(transport).classify("open notes") }
        #expect(result == .failure(.unsupportedAction("open_app")))
        #expect(transport.callCount == 1)
    }

    @Test func controlPhrasesNeverReachTheModel() async throws {
        let transport = MockTransport([])
        let intent = try await capture { try await Fixtures.classifier(transport).classify("Flow, stop") }.get()
        #expect(intent.control == .stop)
        #expect(transport.callCount == 0)
    }

    @Test func emptyAndOversizedInputRejectedLocally() async {
        let transport = MockTransport([])
        let classifier = Fixtures.classifier(transport)
        #expect(await capture { try await classifier.classify("   ") } == .failure(.emptyInput))
        let long = String(repeating: "a", count: BonsaiIntentClassifier.maxInputLength + 1)
        #expect(await capture { try await classifier.classify(long) } == .failure(.inputTooLong(limit: 500)))
        #expect(transport.callCount == 0)
    }

    @Test func cancellationStopsBeforeRequest() async {
        let transport = MockTransport([Fixtures.completion(Fixtures.intentJSON(action: "activate_app", target: "notes"))])
        let classifier = Fixtures.classifier(transport)
        let task = Task { await capture { try await classifier.classify("open notes") } }
        task.cancel()
        let result = await task.value
        // Either cancelled before the request or completed; never an unrelated error.
        switch result {
        case .failure(.cancelled), .success: break
        default: Issue.record("unexpected \(result)")
        }
    }
}
