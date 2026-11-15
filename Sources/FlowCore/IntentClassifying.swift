import Foundation

/// The router interface the app depends on. Implementations must throw
/// `ClassificationError` and must never execute anything.
public protocol IntentClassifying: Sendable {
    func classify(_ utterance: String) async throws(ClassificationError) -> Intent
}

/// Deterministic handling of reserved standalone phrases, run before any model call
/// (spec 02 §3: STOP/CANCEL has priority over LLM calls).
public enum DeterministicRouter {
    /// Words that carry no meaning in a control phrase ("okay Flow, stop now please").
    static let fillers: Set<String> = ["flow", "hey", "ok", "okay", "please", "now", "just", "uh", "um", "right", "thanks", "thank",
                                       "you", "already", "alright", "so", "and", "oh", "actually"]
    /// A clause is a stop when it has a stop word and nothing but these words (after fillers).
    static let stopHeads: Set<String> = ["stop", "quiet", "enough", "pause", "sleep", "silence"]
    static let stopWords: Set<String> = stopHeads.union(["listening", "it", "that", "be", "go", "to", "that's", "thats", "s", "is",
                                                         "talking", "please"])
    static let cancelHeads: Set<String> = ["cancel", "nevermind", "forget"]
    static let cancelWords: Set<String> = cancelHeads.union(["never", "mind", "it", "that", "this", "the", "task", "request", "about"])

    /// stop / cancel, recognized without any model (spec 02 §3). The whole utterance, or its
    /// last clause ("…I'm not sure I can do it. Stop"), must be only a control phrase; a word
    /// like "stop" inside an ordinary sentence ("the bus stop") never counts.
    public static func route(_ utterance: String) -> Intent? {
        let lowered = utterance.lowercased().replacingOccurrences(of: "’", with: "'")
        let clauses = lowered.components(separatedBy: CharacterSet(charactersIn: ".!?;,\n")).map(tokens).filter { !$0.isEmpty }
        let candidates = [tokens(lowered)] + (clauses.count > 1 ? [clauses.last!] : [])
        for words in candidates {
            if let command = classify(words) {
                return Intent(kind: .control, control: command, summary: "Control: \(command.rawValue)", source: .deterministic)
            }
        }
        return nil
    }

    static func tokens(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted).filter { !$0.isEmpty }
    }

    static func classify(_ raw: [String]) -> ControlCommand? {
        let words = raw.filter { !fillers.contains($0) }
        guard !words.isEmpty, words.count <= 5 else { return nil }
        if words.contains("dictation"), words.contains("stop"), Set(words).isSubset(of: ["stop", "dictation", "the", "dictating"]) {
            return .stopDictation
        }
        let set = Set(words)
        if !set.isDisjoint(with: cancelHeads) || (set.contains("never") && set.contains("mind")), set.isSubset(of: cancelWords) {
            return .cancel
        }
        if !set.isDisjoint(with: stopHeads), set.isSubset(of: stopWords) {
            return .stop
        }
        return nil
    }
}
