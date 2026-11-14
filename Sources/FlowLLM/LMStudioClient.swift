import FlowCore
import Foundation

/// Local LM Studio server settings. Construction rejects non-loopback hosts so
/// Flow can never be pointed at cloud inference (PRD principle 6, spec 02 §15).
public struct LMStudioConfiguration: Sendable, Equatable {
    public static let defaultBaseURL = URL(string: "http://localhost:1234/v1")!
    public static let defaultModelID = "ternary-bonsai-2-2b-mlx"

    public let baseURL: URL
    public let modelID: String
    public let requestTimeout: TimeInterval
    public let maxTokens: Int

    public init(
        baseURL: URL = defaultBaseURL,
        modelID: String = defaultModelID,
        requestTimeout: TimeInterval = 60,
        maxTokens: Int = 256
    ) throws(ClassificationError) {
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { throw .invalidConfiguration("URL must be http(s)") }
        guard let host = baseURL.host?.lowercased(),
            ["localhost", "127.0.0.1", "::1"].contains(host)
        else { throw .invalidConfiguration("server must be on this Mac (localhost)") }
        guard !modelID.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw .invalidConfiguration("model ID is empty") }
        guard requestTimeout > 0, maxTokens > 0
        else { throw .invalidConfiguration("timeout and max tokens must be positive") }
        self.baseURL = baseURL
        self.modelID = modelID
        self.requestTimeout = requestTimeout
        self.maxTokens = maxTokens
    }
}

/// Injectable HTTP layer so tests never need a running server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case system, user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct CompletionResult: Sendable, Equatable {
    public let content: String
    public let modelID: String
    public let finishReason: String?
}

/// Minimal client for LM Studio's OpenAI-compatible endpoints
/// (`GET /v1/models`, `POST /v1/chat/completions` with `response_format: json_schema`).
public struct LMStudioClient: Sendable {
    public let configuration: LMStudioConfiguration
    private let transport: HTTPTransport

    public init(configuration: LMStudioConfiguration, transport: HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Model IDs the server reports.
    public func listModels() async throws(ClassificationError) -> [String] {
        var request = URLRequest(url: configuration.baseURL.appending(path: "models"))
        request.timeoutInterval = min(configuration.requestTimeout, 5)
        let data = try await perform(request)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = object["data"] as? [[String: Any]]
        else { throw .httpStatus(code: 200, message: "unexpected /models payload") }
        return entries.compactMap { $0["id"] as? String }
    }

    /// Chat completion constrained to a JSON schema. `schema` is the JSON Schema object.
    public func complete(
        messages: [ChatMessage],
        schemaName: String,
        schema: [String: Any]
    ) async throws(ClassificationError) -> CompletionResult {
        let body: [String: Any] = [
            "model": configuration.modelID,
            "temperature": 0,
            "max_tokens": configuration.maxTokens,
            "stream": false,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ],
        ]
        var request = URLRequest(url: configuration.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw .invalidConfiguration("could not encode request")
        }

        let data = try await perform(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .httpStatus(code: 200, message: "response was not a JSON object")
        }
        let returnedModel = object["model"] as? String ?? ""
        guard returnedModel == configuration.modelID else {
            throw .modelMismatch(expected: configuration.modelID, actual: returnedModel)
        }
        guard
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw .emptyResponse }
        let finish = first["finish_reason"] as? String
        if finish == "length" {
            throw .malformedJSON("output truncated at max_tokens")
        }
        return CompletionResult(content: content, modelID: returnedModel, finishReason: finish)
    }

    private func perform(_ request: URLRequest) async throws(ClassificationError) -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw Self.map(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw .httpStatus(code: response.statusCode, message: Self.serverErrorMessage(data))
        }
        return data
    }

    static func map(_ error: any Error) -> ClassificationError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else {
            return .serverUnavailable(String(describing: error))
        }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        default: return .serverUnavailable(urlError.localizedDescription)
        }
    }

    private static func serverErrorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data.prefix(200), encoding: .utf8)
        }
        if let err = object["error"] as? [String: Any] { return err["message"] as? String }
        return object["error"] as? String
    }
}
