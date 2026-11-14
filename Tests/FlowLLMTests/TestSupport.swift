import FlowCore
@testable import FlowLLM
import Foundation
import Synchronization

/// Scripted transport: returns queued responses in order and records requests.
final class MockTransport: HTTPTransport, Sendable {
    enum Reply: Sendable {
        case http(status: Int, body: String)
        case failure(URLError.Code)
    }

    private let replies: Mutex<[Reply]>
    private let recorded = Mutex<[URLRequest]>([])

    init(_ replies: [Reply]) { self.replies = Mutex(replies) }

    var requests: [URLRequest] { recorded.withLock { $0 } }
    var callCount: Int { requests.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let reply = replies.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        switch reply {
        case .http(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        case nil:
            throw URLError(.cannotConnectToHost)
        }
    }
}

enum Fixtures {
    static let model = LMStudioConfiguration.defaultModelID

    /// An LM Studio chat-completion envelope around `content`.
    static func completion(_ content: String, model: String = model, finish: String = "stop") -> MockTransport.Reply {
        let envelope: [String: Any] = [
            "id": "chatcmpl-test", "object": "chat.completion", "model": model,
            "choices": [["index": 0, "finish_reason": finish,
                         "message": ["role": "assistant", "content": content]]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: envelope)
        return .http(status: 200, body: String(decoding: data, as: UTF8.self))
    }

    static func intentJSON(
        kind: String = "direct", action: String, target: String = "", detail: String = "", summary: String = "s"
    ) -> String {
        let object = ["kind": kind, "action": action, "target": target, "detail": detail, "summary": summary]
        let data = try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }

    static func classifier(_ transport: MockTransport, maxAttempts: Int = 2) -> BonsaiIntentClassifier {
        let client = LMStudioClient(configuration: try! LMStudioConfiguration(), transport: transport)
        return BonsaiIntentClassifier(client: client, maxAttempts: maxAttempts)
    }
}


/// Runs a classification call and captures the typed error as a value, so tests can
/// compare exact `ClassificationError` payloads. Any other error type crashes the test loudly.
func capture<T>(_ body: () async throws -> T) async -> Result<T, ClassificationError> {
    do { return .success(try await body()) } catch let error as ClassificationError {
        return .failure(error)
    } catch {
        preconditionFailure("non-ClassificationError escaped: \(error)")
    }
}

func validate(_ json: String) -> Result<Intent, ClassificationError> {
    do { return .success(try IntentValidator.validate(json, modelID: Fixtures.model)) } catch { return .failure(error) }
}
