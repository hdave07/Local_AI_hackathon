import FlowCore
import FlowPlanner
import FlowRouting
import FlowSession
import Foundation

/// Why Flow is speaking. Questions, confirmations and failures are always spoken;
/// outcomes only when they carry information (spec 02 §11/§13, PRD §7.4).
public enum CueKind: String, Sendable, Equatable {
    case question
    case confirmation
    case failure
    case outcome
    case interruption
    case reminder
    case notice
}

public struct SpeechCue: Sendable, Equatable {
    public let kind: CueKind
    public let text: String

    public init(_ kind: CueKind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Decides what to say for each voice-session turn. Pure and deterministic.
public struct FeedbackPolicy: Sendable, Equatable {
    public enum Verbosity: String, Sendable, Equatable {
        /// Only questions, confirmations, failures and interruptions.
        case minimal
        /// Plus informational outcomes (draft shown, sent, calendar answers, declined requests).
        case normal
        /// Plus a short "Done." for silent routine successes.
        case verbose
    }

    public var verbosity: Verbosity

    public init(verbosity: Verbosity = .normal) {
        self.verbosity = verbosity
    }

    /// The cue for a finished turn, given the task phase the coordinator reports after it.
    public func cue(for turn: SessionTurn, phase: TaskPhase) -> SpeechCue? {
        let said = Self.clean(turn.say.joined(separator: " "))
        switch turn.state {
        case .awaitingChoice(let question):
            return SpeechCue(.question, Self.spokenChoice(question))
        case .awaitingConfirmation(let request):
            return SpeechCue(.confirmation, Self.spokenConfirmation(request))
        case .cancelled:
            // Say what was cancelled when the session explains it ("Okay, I won't send it…").
            return verbosity == .minimal ? nil : SpeechCue(.interruption, said.isEmpty ? "Stopped." : said)
        case .stopped(_, let reason):
            return SpeechCue(.failure, Self.clean(reason))
        case .idle, .running, .completed:
            if case .awaitingAnswer = phase, !said.isEmpty { return SpeechCue(.question, said) }
            if said.isEmpty {
                // Routine low-risk success (e.g. "open notes"): the HUD is enough.
                return verbosity == .verbose && turn.planSummary != nil ? SpeechCue(.outcome, "Done.") : nil
            }
            return verbosity == .minimal ? nil : SpeechCue(.outcome, said)
        }
    }

    /// Spoken when the microphone or recognizer stops on its own.
    public func cue(forListenChange old: ListenStatus, _ new: ListenStatus) -> SpeechCue? {
        guard case .failed(let message) = new else { return nil }
        if case .failed = old { return nil }
        return SpeechCue(.failure, "I stopped listening. \(Self.clean(message))")
    }

    /// A short reminder for an unanswered question.
    public func reminder(for phase: TaskPhase) -> SpeechCue? {
        switch phase {
        case .awaitingChoice(let prompt, _):
            return SpeechCue(.reminder, "Still waiting. " + (Self.leadingQuestion(prompt) ?? "Which one?"))
        case .awaitingConfirmation:
            return SpeechCue(.reminder, "Still waiting. Should I send it? Say yes or no.")
        case .awaitingAnswer(let question):
            return SpeechCue(.reminder, "Still waiting. " + Self.clean(question))
        default:
            return nil
        }
    }

    // MARK: - Rendering

    /// "Which Sarah? Sarah Chen, Meeting tomorrow; or Sarah Okafor, Lunch on Friday."
    public static func spokenChoice(_ q: PlanQuestion) -> String {
        guard !q.candidates.isEmpty else { return clean(q.prompt) }
        let firstNames = q.candidates.map { $0.sender.split(separator: " ").first.map(String.init) ?? $0.sender }
        let shared = Set(firstNames.map { $0.lowercased() }).count == 1 ? firstNames[0] : nil
        let head = shared.map { "Which \($0)?" } ?? "Which one?"
        let shown = q.candidates.prefix(3).map { c in
            [c.sender, clean(c.subject)].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        var options = shown.count > 1 ? shown.dropLast().joined(separator: "; ") + "; or " + shown.last! : shown.joined()
        if q.candidates.count > 3 { options += "; and \(q.candidates.count - 3) more. Say a name or a number" }
        return "\(head) \(options)."
    }

    /// "Send this by mail to sarah.chen@example.com? “I can meet at 3.” Say yes to send it, or no."
    public static func spokenConfirmation(_ r: ApprovalRequest) -> String {
        let to = r.draft.recipients.joined(separator: " and ")
        let channel = r.draft.channel == .mail ? "email" : r.draft.channel.rawValue
        let own = SendWording.ownText(r.draft.body)  // the quoted original is not read aloud
        let body = clean(own.text) + (own.quoted ? ", followed by the quoted original" : "")
        return "Send this \(channel) to \(to)? It says: \(body). Say yes to send it, or no."
    }

    static func leadingQuestion(_ prompt: String) -> String? {
        guard let r = prompt.range(of: "Which [^?]*\\?", options: .regularExpression) else { return nil }
        return String(prompt[r])
    }

    /// Removes text that reads badly aloud: bracketed tags ("[FlowTest]"), typographic quotes,
    /// and duplicate whitespace.
    public static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[[^\]]{1,24}\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
