import FlowPlanner
import FlowSession
import FlowSpeech
import Foundation

// Floating HUD state (ADR 0011). A pure projection of the existing voice-session events
// (`CoordinatorEvent`) and spoken-feedback events (`FeedbackEvent`). It holds no task
// context of its own: what Flow is waiting for comes from the coordinator's `TaskPhase`,
// which mirrors the planner's `RunState` and the router's pending question.

/// What Flow is doing right now, most important first.
public enum HUDActivity: String, Sendable, Equatable {
    case idle
    case listening
    /// Interim words are arriving.
    case hearing
    /// A command is being handled.
    case processing
    case speaking
    case awaitingChoice
    case awaitingConfirmation
    case awaitingAnswer
    case error

    public var label: String {
        switch self {
        case .idle: "Not listening"
        case .listening: "Listening"
        case .hearing: "Hearing you…"
        case .processing: "Working…"
        case .speaking: "Speaking"
        case .awaitingChoice: "Waiting for your choice"
        case .awaitingConfirmation: "Waiting for your confirmation"
        case .awaitingAnswer: "Waiting for your answer"
        case .error: "Needs attention"
        }
    }
}

public struct HUDChoice: Sendable, Equatable, Identifiable {
    public let number: Int
    public let text: String
    public var id: Int { number }
}

/// How the last command ended, as the planner reported it.
public enum HUDOutcomeKind: String, Sendable, Equatable {
    /// Completed and verified by the executor.
    case verified
    /// Stopped: failed, unverified, refused, or unsupported. The text says why.
    case notDone
    /// stop / cancel.
    case cancelled
    /// Informational (a question was asked, nothing executed yet).
    case info
}

public struct HUDOutcome: Sendable, Equatable {
    public let kind: HUDOutcomeKind
    public let text: String
}

/// One recent exchange, kept short (no message bodies): what was heard and how it ended.
public struct HUDEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let heard: String
    public let result: HUDOutcomeKind
    public let summary: String
}

public struct HUDState: Sendable, Equatable {
    public static let maxRecent = 4
    public static let maxOutcomeLength = 220
    public static let maxRecentLength = 80

    // From the coordinator.
    public private(set) var listen: ListenStatus = .off
    public private(set) var phase: TaskPhase = .idle
    /// Interim words (display only, never routed).
    public private(set) var hearing: String?
    /// The latest finalized utterance.
    public private(set) var lastHeard: String?
    public private(set) var outcome: HUDOutcome?
    public private(set) var recent: [HUDEntry] = []
    // From spoken feedback.
    public private(set) var speaking: String?
    public private(set) var voiceNote: String?
    /// The last utterance dropped as Flow's own speech (shown so the user knows it was ignored).
    public private(set) var ignored: String?
    // Presentation (user controlled).
    public private(set) var collapsed = false
    public private(set) var hidden = false

    public init() {}

    // MARK: Derived

    public var listening: Bool {
        switch listen {
        case .starting, .listening, .hearing: true
        default: false
        }
    }

    public var errorMessage: String? {
        if case .failed(let message) = listen { return message }
        return nil
    }

    /// Flow needs the user to say something before the task can continue.
    public var expectsResponse: Bool {
        switch phase {
        case .awaitingChoice, .awaitingConfirmation, .awaitingAnswer: true
        default: false
        }
    }

    public var activity: HUDActivity {
        if errorMessage != nil { return .error }
        if speaking != nil { return .speaking }
        switch phase {
        case .awaitingChoice: return .awaitingChoice
        case .awaitingConfirmation: return .awaitingConfirmation
        case .awaitingAnswer: return .awaitingAnswer
        case .working: return .processing
        case .idle, .finished: break
        }
        if case .hearing = listen { return .hearing }
        return listening ? .listening : .idle
    }

    /// The open question, verbatim from the planner or router.
    public var question: String? {
        switch phase {
        case .awaitingChoice(let prompt, _): Self.leadingQuestion(prompt) ?? prompt
        case .awaitingConfirmation(let prompt): prompt
        case .awaitingAnswer(let question): question.isEmpty ? nil : question
        default: nil
        }
    }

    public var isConfirmation: Bool {
        if case .awaitingConfirmation = phase { return true }
        return false
    }

    /// Numbered choices when the planner needs disambiguation ("1. Sarah Chen — …").
    public var choices: [HUDChoice] {
        guard case .awaitingChoice(_, let options) = phase else { return [] }
        return options.enumerated().map { i, option in
            HUDChoice(number: i + 1, text: Self.stripNumber(option))
        }
    }

    /// What the user can say next.
    public var hint: String {
        switch activity {
        case .awaitingChoice: return "Say a number or a name, like “the first one”. Say “cancel” to stop."
        case .awaitingConfirmation: return "Say “yes, send it” to send, or “no”. Nothing is sent without a clear yes."
        case .awaitingAnswer: return "Answer the question, or say “cancel”."
        case .error: return "Fix the problem above, then start listening again."
        case .processing: return "Say “stop” to interrupt."
        case .speaking:
            return expectsResponse ? "Answer when Flow finishes speaking, or say “Flow, stop”." : "Say “Flow, stop” to interrupt."
        case .hearing, .listening: return "Say a command, like “open Notes” or “find Sarah's email”."
        case .idle: return "Start listening to talk to Flow."
        }
    }

    // MARK: Reducer

    public enum Input: Sendable, Equatable {
        case coordinator(CoordinatorEvent)
        case feedback(FeedbackEvent)
        case setCollapsed(Bool)
        case setHidden(Bool)
    }

    public mutating func apply(_ input: Input) {
        switch input {
        case .coordinator(let event): apply(event)
        case .feedback(let event): apply(event)
        case .setCollapsed(let on): collapsed = on
        case .setHidden(let on): hidden = on
        }
    }

    mutating func apply(_ event: CoordinatorEvent) {
        switch event {
        case .status(let status):
            listen = status.listen
            if case .hearing(let words) = status.listen { hearing = words.isEmpty ? nil : words } else { hearing = nil }
            let newQuestion = status.task != phase
            phase = status.task
            if expectsResponse, newQuestion {
                // A question must never be missed: show and expand the HUD (the user can collapse it again).
                hidden = false
                collapsed = false
            }
        case .finalized(let text):
            lastHeard = Self.truncate(text, Self.maxOutcomeLength)
            hearing = nil
            ignored = nil
        case .incomplete:
            hearing = nil
        case .turn(let turn):
            // A turn that ran no plan (a question, a refusal) is information, never a verified success.
            let kind = turn.planSummary == nil && Self.kind(of: turn.state) == .verified ? .info : Self.kind(of: turn.state)
            let said = turn.say.joined(separator: " ")
            let text: String
            switch turn.state {
            case .stopped(_, let reason): text = reason
            case .cancelled: text = said.isEmpty ? "Stopped." : said
            case .awaitingChoice, .awaitingConfirmation: text = ""  // shown as the question instead
            default: text = said.isEmpty ? (turn.planSummary.map { "Done: \($0)." } ?? "") : said
            }
            outcome = text.isEmpty ? nil : HUDOutcome(kind: kind, text: Self.truncate(text, Self.maxOutcomeLength))
            if turn.source == .typed || lastHeard == nil { lastHeard = Self.truncate(turn.utterance, Self.maxOutcomeLength) }
            let summary = text.isEmpty ? (Self.leadingQuestion(said) ?? "Asked a question") : text
            recent.insert(HUDEntry(id: turn.id, heard: Self.truncate(turn.utterance, Self.maxRecentLength), result: kind,
                                   summary: Self.truncate(summary, Self.maxRecentLength)), at: 0)
            if recent.count > Self.maxRecent { recent.removeLast(recent.count - Self.maxRecent) }
        }
    }

    mutating func apply(_ event: FeedbackEvent) {
        switch event {
        case .status(let status):
            switch status {
            case .speaking(let text): speaking = Self.truncate(text, Self.maxOutcomeLength)
            case .ready: speaking = nil; voiceNote = nil
            case .muted: speaking = nil; voiceNote = "Spoken feedback is muted."
            case .unavailable(let why): speaking = nil; voiceNote = "Spoken feedback is off: \(why)"
            }
        case .ignored(let utterance, _):
            ignored = Self.truncate(utterance, Self.maxRecentLength)
        case .timedOut(let what):
            if what == "confirmation" {
                outcome = HUDOutcome(kind: .cancelled, text: "No answer, so nothing was sent.")
            }
        case .spoke, .interrupted, .skipped:
            break
        }
    }

    // MARK: Helpers

    static func kind(of state: RunState) -> HUDOutcomeKind {
        switch state {
        case .completed: .verified
        case .stopped: .notDone
        case .cancelled: .cancelled
        case .idle, .running, .awaitingChoice, .awaitingConfirmation: .info
        }
    }

    /// "I found 3 messages: 1. … Which one?" → "Which one?"; keeps prompts without a list.
    static func leadingQuestion(_ prompt: String) -> String? {
        guard prompt.contains(where: { $0 == "?" }) else { return nil }
        if let r = prompt.range(of: #"(?:Which|What|Who|Should|Do|Did|Is|Are)[^?.:;]*\?"#, options: .regularExpression) {
            return String(prompt[r])
        }
        return nil
    }

    static func stripNumber(_ option: String) -> String {
        option.replacingOccurrences(of: #"^\s*\d+[.)]\s*"#, with: "", options: .regularExpression)
    }

    public static func truncate(_ s: String, _ max: Int) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count <= max ? flat : String(flat.prefix(max - 1)) + "…"
    }
}
