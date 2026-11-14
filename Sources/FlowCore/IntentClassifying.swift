import Foundation

/// The router interface the app depends on. Implementations must throw
/// `ClassificationError` and must never execute anything.
public protocol IntentClassifying: Sendable {
    func classify(_ utterance: String) async throws(ClassificationError) -> Intent
}

/// Deterministic handling of reserved standalone phrases, run before any model call
/// (spec 02 §3: STOP/CANCEL has priority over LLM calls).
public enum DeterministicRouter {
    public static func route(_ utterance: String) -> Intent? {
        let words = utterance.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        // Optional leading wake word "Flow".
        let body = words.first == "flow" ? Array(words.dropFirst()) : words
        let command: ControlCommand?
        switch body {
        case ["stop"]: command = .stop
        case ["cancel"]: command = .cancel
        case ["stop", "dictation"]: command = .stopDictation
        default: command = nil
        }
        guard let command else { return nil }
        return Intent(
            kind: .control, control: command,
            summary: "Control: \(command.rawValue)", source: .deterministic)
    }
}
