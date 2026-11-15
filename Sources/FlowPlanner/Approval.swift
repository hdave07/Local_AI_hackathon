import FlowCore
import FlowRouting
import Foundation

/// Consequential actions that need explicit, bound approval (spec 02 §6 EXTERNAL/DESTRUCTIVE).
/// Delete has no FlowCore action yet (the MVP declines it), but approvals are typed so it
/// can be added without changing the mechanism.
public enum ConsequentialAction: String, Sendable, Equatable {
    case send
    case delete
}

/// What the user is asked to approve: exactly this action on exactly this draft state.
public struct ApprovalRequest: Sendable, Equatable {
    public let stepID: Int
    public let action: ConsequentialAction
    public let draft: DraftSnapshot
    public let prompt: String
    /// When the question was asked; an unanswered confirmation expires (never sends).
    public let askedAt: Date

    public init(stepID: Int, action: ConsequentialAction, draft: DraftSnapshot, prompt: String, askedAt: Date = .distantPast) {
        self.stepID = stepID
        self.action = action
        self.draft = draft
        self.prompt = prompt
        self.askedAt = askedAt
    }
}

/// How a reply to a send confirmation is read (spec 02 §3 CONFIRMING: "exact spoken yes").
///
/// Only an explicit yes approves: "yes", "yes, send it", "yeah, send it now". Vague assent
/// ("sure", "okay", "go ahead"), a repeated "send it" and anything with extra content are
/// *not* approvals; Flow asks again. Any negation or cancel phrase declines. Flow's own
/// spoken prompt contains "no", so an echo of it can never approve.
public enum ConfirmationReply: Sendable, Equatable {
    case approve
    case decline
    /// Read the draft again and keep waiting.
    case readBack
    /// Not an explicit answer; ask again (the confirmation stays open).
    case unclear
    /// Not about this confirmation at all (e.g. a new command); handled by the caller.
    case unrelated

    static let affirmatives: Set<String> = ["yes", "yeah", "yep"]
    /// Words allowed alongside an affirmative ("yes, send it now please").
    static let fillers: Set<String> = [
        "send", "it", "please", "that", "this", "the", "email", "reply", "message", "draft", "now", "flow", "do", "go", "ahead",
        "sure", "okay", "ok", "uh", "um", "i", "confirm", "confirmed", "correct", "right",
    ]
    static let negatives: Set<String> = [
        "no", "nope", "don't", "dont", "not", "wait", "hold", "cancel", "stop", "never", "mind", "nevermind", "forget", "later",
        "actually", "nah",
    ]
    static let vague: Set<String> = ["sure", "okay", "ok", "go", "ahead", "fine", "alright", "right", "correct", "confirm", "send", "it", "do"]
    static let editWords: Set<String> = [
        "change", "replace", "add", "also", "instead", "make", "remove", "delete", "undo", "fix", "rewrite", "insert", "append",
    ]
    static let readWords: Set<String> = ["read", "repeat", "again", "say", "what", "show", "review"]

    public static func parse(_ utterance: String) -> ConfirmationReply {
        let words = utterance.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        let w = Set(words)
        guard !w.isEmpty else { return .unclear }
        // "Actually, change 3:30 to 4": an edit, not an answer. The caller abandons the
        // confirmation and runs it; the edited draft needs a new review and yes.
        if !w.isDisjoint(with: editWords) { return .unrelated }
        if !w.isDisjoint(with: negatives) { return .decline }
        if !w.isDisjoint(with: affirmatives), w.subtracting(affirmatives).isSubset(of: fillers) { return .approve }
        if !w.isDisjoint(with: readWords), w.isDisjoint(with: affirmatives) { return .readBack }
        if w.isSubset(of: vague.union(fillers)) { return .unclear }  // "sure", "okay go ahead", "send it"
        return .unrelated
    }
}

/// What Flow says to ask for, re-ask for, and report on a send (shared by the runner and speech).
public enum SendWording {
    /// The quoted original Mail appends to a reply is not read aloud ("On … wrote:").
    public static func ownText(_ body: String) -> (text: String, quoted: Bool) {
        let lines = body.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.range(of: #"^On .+ wrote:\s*$"#, options: .regularExpression) != nil }) {
            return (lines[..<i].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), true)
        }
        return (body.trimmingCharacters(in: .whitespacesAndNewlines), false)
    }

    public static func confirmation(_ draft: DraftSnapshot, channelName: String) -> String {
        let to = draft.recipients.joined(separator: " and ")
        let own = ownText(draft.body)
        let subject = draft.subject.isEmpty ? "" : ", subject “\(draft.subject)”"
        let quoted = own.quoted ? " (followed by the quoted original)" : ""
        return "Ready to send this \(channelName) to \(to)\(subject). It says: “\(own.text)”\(quoted). Say “yes, send it” to send, or “no”."
    }

    public static let reprompt = "I need a clear yes before sending. Say “yes, send it” to send, or “no”."
    public static let declined = "Okay, I won't send it. The draft is still open."
    public static let expired = "That confirmation expired, so nothing was sent. Say “send it” when you're ready."
}

/// A single-use approval bound to draft identity, version and content hash (spec 02 §3,
/// PRD §7.5). Any change to recipients, subject or body produces a different hash.
public struct Approval: Sendable, Equatable {
    public let id: UUID
    public let action: ConsequentialAction
    public let draftID: String
    public let draftVersion: Int
    public let contentHash: String
    public let issuedAt: Date
    public let expiresAt: Date

    public static let lifetime: TimeInterval = 120

    public init(id: UUID = UUID(), action: ConsequentialAction, draft: DraftSnapshot, issuedAt: Date) {
        self.id = id
        self.action = action
        self.draftID = draft.id
        self.draftVersion = draft.version
        self.contentHash = draft.contentHash
        self.issuedAt = issuedAt
        self.expiresAt = issuedAt.addingTimeInterval(Self.lifetime)
    }

    /// Still valid for this action on this exact draft state at `now`.
    public func authorizes(_ action: ConsequentialAction, on draft: DraftSnapshot, now: Date) -> Bool {
        self.action == action && draftID == draft.id && draftVersion == draft.version
            && contentHash == draft.contentHash && now < expiresAt
    }
}

/// At-most-once sending (spec 02 §3): a draft is sent once; an unverified send is never
/// retried automatically and blocks further sends until reconciled.
public struct SendLedger: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        /// Dispatched; result not yet known.
        case inFlight = "in_flight"
        case sent
        /// Timed out or could not be verified. Mail may or may not have sent it.
        case unverified
        /// Dry-run mode: every check passed and the send was recorded, not performed.
        case rehearsed
    }

    public private(set) var records: [String: Outcome] = [:]

    public init() {}

    /// Why sending `draftID` must not happen now, or nil if it may.
    public func refusal(for draftID: String) -> String? {
        switch records[draftID] {
        case nil: nil
        case .sent: "That draft was already sent."
        case .inFlight: "That draft is already being sent."
        case .unverified: "I couldn't confirm the last send. Check the conversation or Sent folder before sending again."
        case .rehearsed: "I already did a dry-run send of that draft. Nothing was sent."
        }
    }

    public mutating func record(_ draftID: String, _ outcome: Outcome) {
        records[draftID] = outcome
    }

    /// The executor refused before sending (e.g. approval did not match the live draft).
    public mutating func clearInFlight(_ draftID: String) {
        if records[draftID] == .inFlight { records[draftID] = nil }
    }

    /// The user or executor confirmed the unverified send did not go out.
    public mutating func reconcileNotSent(_ draftID: String) {
        if records[draftID] == .unverified { records[draftID] = nil }
    }
}
