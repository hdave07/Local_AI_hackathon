import Foundation

/// Typed, never-silent classification failures (plan 03 §3 "Errors typed, never silent").
public enum ClassificationError: Error, Sendable, Equatable {
    case emptyInput
    case inputTooLong(limit: Int)
    case invalidConfiguration(String)
    /// Connection refused / host unreachable / server not running.
    case serverUnavailable(String)
    case timedOut
    case httpStatus(code: Int, message: String?)
    /// Server answered with a model other than the one requested. LM Studio has
    /// been observed to serve the loaded model for an unknown model ID.
    case modelMismatch(expected: String, actual: String)
    case emptyResponse
    case malformedJSON(String)
    case schemaViolation(String)
    case unsupportedAction(String)
    case unsupportedTarget(action: String, target: String)
    case inconsistentIntent(String)
    case cancelled

    /// Safe to retry automatically? Classification never has side effects, but
    /// only transient model-output problems are worth an automatic retry.
    public var retrySafe: Bool {
        switch self {
        case .malformedJSON, .emptyResponse: true
        default: false
        }
    }

    /// Concise one-line message for the HUD (spec 02 §13: no wall of technical detail).
    public var userMessage: String {
        switch self {
        case .emptyInput: "Say or type a command."
        case .inputTooLong(let limit): "That command is too long (limit \(limit) characters)."
        case .invalidConfiguration(let why): "Model settings are invalid: \(why)"
        case .serverUnavailable: "Can't reach LM Studio. Start its local server and try again."
        case .timedOut: "The local model took too long. Try again."
        case .httpStatus(let code, _): "LM Studio returned an error (HTTP \(code))."
        case .modelMismatch(let expected, let actual):
            "LM Studio answered with “\(actual)” instead of “\(expected)”. Load the Bonsai model."
        case .emptyResponse: "The model returned nothing. Try rephrasing."
        case .malformedJSON: "The model's answer wasn't valid JSON, so it was rejected."
        case .schemaViolation(let why): "The model's answer was rejected: \(why)"
        case .unsupportedAction(let a): "“\(a)” isn't an action Flow supports."
        case .unsupportedTarget(let a, let t): "Flow can't use “\(t)” as the target of \(a)."
        case .inconsistentIntent(let why): "The model's answer was inconsistent: \(why)"
        case .cancelled: "Cancelled."
        }
    }
}
