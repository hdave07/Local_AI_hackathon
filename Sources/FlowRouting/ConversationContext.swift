import FlowCore
import Foundation

/// Minimal task context for resolving references such as "it", "that window" or "her".
///
/// Track B-local stand-in for the plan 03 §3 `TaskContext`. It is built from intents
/// Flow has *proposed* (and, later, from executor-verified state supplied by Track A
/// via `IntentRouter.updateContext`). It never overrides an explicit name in the
/// utterance, and every reference it resolves must be unique; otherwise the router asks.
public struct ConversationContext: Sendable, Equatable {
    /// App most recently activated or targeted.
    public var activeApp: KnownApp?
    /// People in the recent conversation, most recent first (deduplicated, at most 3).
    public var recentPeople: [String]
    /// Description/query of the message currently open, if any.
    public var openMessage: String?
    /// A Flow-authored draft is open.
    public var hasDraft: Bool
    /// Text Flow last inserted or replaced (target for "change that to …").
    public var lastEditedText: String?
    /// An unanswered clarification question.
    public var pending: PendingQuestion?
    /// The last proposed action was about the calendar, so a bare time ("what about Friday?",
    /// "and at five?") continues it.
    public var calendarTopic: Bool = false

    // Verified state, written only from executor results (FlowPlanner). Proposal-level
    // fields above remain for single-intent routing.
    /// Message the executor opened and verified.
    public var selectedMessage: MessageRef?
    /// Current Flow-authored draft as observed in the compose window.
    public var draft: DraftSnapshot?
    /// Draft version last presented for review (send requires the current version).
    public var reviewedDraftVersion: Int?
    /// Window the executor last verified.
    public var selectedWindow: SelectedWindow?
    /// When the context last changed; stale context is ignored.
    public var updatedAt: Date?

    public static let maxPeople = 3

    public init(
        activeApp: KnownApp? = nil, recentPeople: [String] = [], openMessage: String? = nil, hasDraft: Bool = false,
        lastEditedText: String? = nil, pending: PendingQuestion? = nil, updatedAt: Date? = nil,
        selectedMessage: MessageRef? = nil, draft: DraftSnapshot? = nil, reviewedDraftVersion: Int? = nil,
        selectedWindow: SelectedWindow? = nil
    ) {
        self.activeApp = activeApp
        self.recentPeople = recentPeople
        self.openMessage = openMessage
        self.hasDraft = hasDraft
        self.lastEditedText = lastEditedText
        self.pending = pending
        self.updatedAt = updatedAt
        self.selectedMessage = selectedMessage
        self.draft = draft
        self.reviewedDraftVersion = reviewedDraftVersion
        self.selectedWindow = selectedWindow
    }

    /// The current draft was presented for review in exactly its current version.
    public var draftReviewed: Bool {
        guard let draft, let reviewed = reviewedDraftVersion else { return false }
        return draft.version == reviewed
    }

    public static let empty = ConversationContext()

    /// The context as of `now`: empty if older than `ttl`.
    public func fresh(now: Date, ttl: TimeInterval) -> ConversationContext {
        guard let updatedAt else { return self }
        return now.timeIntervalSince(updatedAt) > ttl ? .empty : self
    }

    public mutating func notePerson(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentPeople.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentPeople.insert(trimmed, at: 0)
        if recentPeople.count > Self.maxPeople { recentPeople.removeLast(recentPeople.count - Self.maxPeople) }
    }

    /// Update from a delivered (proposed) action.
    public mutating func record(_ action: FlowAction, now: Date) {
        switch action {
        case .queryCalendar, .showCalendar: calendarTopic = true
        default: calendarTopic = false
        }
        switch action {
        case .activateApp(let app):
            activeApp = app
        case .moveWindow(.app(let app), _), .resizeWindow(.app(let app), _):
            activeApp = app
        case .moveWindow, .resizeWindow:
            break
        case .tileWindows:
            activeApp = nil  // focus after tiling is not known
        case .createDraft(let recipient, _):
            notePerson(recipient)
            hasDraft = true
            activeApp = .mail
        case .readMessage(let query):
            openMessage = query
            if let person = Self.person(inQuery: query) { notePerson(person) }
            activeApp = .mail
        case .queryCalendar:
            break
        case .showCalendar:
            activeApp = .calendar
        case .insertText(let text):
            lastEditedText = text
        case .replaceText(_, let new):
            lastEditedText = new
        case .requestSend:
            hasDraft = false
        case .clickElement, .focus, .scroll, .requestReview:
            break
        case .editText:
            break  // the edited draft's verified state arrives from the executor (`draft`)
        }
        updatedAt = now
    }

    /// "email from priya about the invoice" → "priya"; "sarah's email" → "sarah".
    public static func person(inQuery query: String) -> String? {
        if let m = Rx(#".*?\bfrom\s+([a-z][a-z'.-]*).*"#).match(query), let name = m[0], !nonNames.contains(name.lowercased()) {
            return name
        }
        if let m = Rx(#"(?:.*?\s)?([a-z][a-z.-]*)'s\b.*"#).match(query), let name = m[0], !nonNames.contains(name.lowercased()) {
            return name
        }
        return nil
    }

    static let nonNames: Set<String> = [
        "her", "him", "them", "me", "it", "that", "this", "the", "my", "all", "everyone", "everybody", "someone", "today",
        "yesterday", "tomorrow", "work", "home", "there", "from", "about", "to", "and", "a", "an", "for", "with",
        "saying", "back", "you", "us", "again", "now", "later", "ye", "thee", "thou", "yall", "y'all", "we", "they",
        "he", "she", "i",
    ]
}

/// A clarification question awaiting the user's answer, with what to do once answered.
public enum PendingQuestion: Sendable, Equatable {
    /// Which app? Then perform `then` on it.
    case app(then: AppFollowUp)
    /// Which person? Candidates may be empty (open question).
    case person(candidates: [String], then: PersonFollowUp)
    /// Where should the window go?
    case position(window: WindowTarget)
    /// Which existing text should become `replacement`?
    case textToReplace(replacement: String)
    /// Yes → `proposed`, no → `otherwise` (e.g. "Did you mean 3:30?").
    case confirm(proposed: FlowAction, otherwise: FlowAction, kind: IntentKind)
    /// "Which day or time should I check?" The answer is a time expression.
    case calendarTime
    /// A paused plan is waiting for this answer (FlowPlanner resolves it, not the router).
    case plan(prompt: String, options: [String])
    /// FlowText asked about the draft (which occurrence; keep or discard a preview). A short
    /// answer goes back to it as `edit_text`; anything else drops the question.
    case textEdit(prompt: String, options: [String])
    /// "What should the reply say?" for a reply to the open message; the answer is the content.
    case draftContent(recipient: String)

    public enum AppFollowUp: Sendable, Equatable {
        case activate
        case move(WindowPosition)
        case resize(ResizeChange)
    }

    public enum PersonFollowUp: Sendable, Equatable {
        case draft(content: String)
        case search(rest: String)
    }
}
