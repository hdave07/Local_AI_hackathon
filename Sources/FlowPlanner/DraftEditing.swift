import FlowCore
import FlowRouting
import FlowText
import Foundation

/// Runs `edit_text` against a draft with FlowText and maps the outcome to an
/// `ExecutionResult` (T-023B, ADR 0010). Shared by `MockExecutor` and the real executor so
/// both report edits the same way.
///
/// One `TextEditingSession` per draft keeps that draft's undo history and any open
/// question (which occurrence; keep or discard a preview). *Which* draft is current stays
/// in FlowRouting's `ConversationContext`; this only holds per-draft edit history.
public actor DraftEditSessions {
    private var sessions: [String: TextEditingSession] = [:]

    public init() {}

    /// The session for `draftID`, created with `backend` the first time.
    public func session(for draftID: String, backend: @Sendable () -> any TextBackend) -> TextEditingSession {
        if let s = sessions[draftID] { return s }
        let s = TextEditingSession(document: Self.documentID(draftID), backend: backend())
        sessions[draftID] = s
        return s
    }

    /// The draft is gone (sent, discarded, closed): drop its history.
    public func forget(_ draftID: String) { sessions[draftID] = nil }

    public static func documentID(_ draftID: String) -> TextDocumentID { TextDocumentID("mail-draft:\(draftID)") }

    /// Runs `command` and maps the outcome. `reread` returns the live draft after the edit
    /// (the executor's own verification); the observation is always that re-read draft.
    public static func run(_ command: String, in session: TextEditingSession,
                           reread: @Sendable () async -> DraftSnapshot?) async -> ExecutionResult {
        let outcome = await session.handle(command)
        switch outcome {
        case .applied(let e), .undone(let e):
            guard let live = await reread() else {
                return ExecutionResult(status: .unverified, error: .targetNotFound,
                                       userMessage: "I changed the draft but couldn't read it back. Say “what does the draft say?” to check.")
            }
            guard Self.shows(live.body, e.snapshot.text) else {
                // Something other than Flow's change is on screen: never report success.
                return ExecutionResult(status: .unverified, observation: .draft(live), error: .draftChanged,
                                       userMessage: "The draft doesn't show the change I made. Say “what does the draft say?” to check.")
            }
            let what = if case .undone = outcome { "Undone." } else { "\(e.summary)." }
            return ExecutionResult(status: .completed, observation: .draft(live),
                                   userMessage: "\(what) The draft now says: “\(e.snapshot.text)”")
        case .choose(let prompt, let options):
            return ExecutionResult(status: .needsClarification, observation: .textChoice(prompt: prompt, options: options), retrySafe: true)
        case .preview(let p):
            return ExecutionResult(status: .needsClarification, observation: .textChoice(prompt: p.prompt, options: []), retrySafe: true)
        case .discarded:
            let live = await reread()
            return ExecutionResult(status: .completed, observation: live.map(Observation.draft) ?? .none,
                                   userMessage: "Okay, I left the draft as it was.")
        case .cancelled:
            return ExecutionResult(status: .cancelled, userMessage: "Stopped. The draft wasn't changed.")
        case .refused(let why):
            return ExecutionResult(status: .failed, error: why.contains("changed outside Flow") ? .draftChanged : .unknown,
                                   retrySafe: true, userMessage: why)
        case .notFound(let why):
            return ExecutionResult(status: .failed, error: .targetNotFound, retrySafe: true, userMessage: why)
        case .nothingToUndo:
            return ExecutionResult(status: .failed, error: .targetNotFound, retrySafe: true,
                                   userMessage: "There's no change of mine to undo in this draft.")
        case .failed(let why):
            return ExecutionResult(status: .failed, error: .unknown, userMessage: why)
        case .notHandled, .dictationStarted, .dictationEnded:
            return ExecutionResult(status: .unsupported, userMessage: "I can't make that change to the draft.")
        }
    }

    /// Whether the re-read draft body shows exactly the edited text: the whole body, or its
    /// authored part above a quoted original (`AuthoredText`). Whitespace runs are compared
    /// loosely because an on-screen body (Accessibility) reflows spaces and blank lines; the
    /// backend has already verified the exact characters.
    static func shows(_ body: String, _ text: String) -> Bool {
        func n(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return body == text || n(body) == n(text) || n(AuthoredText.split(body).authored) == n(text)
    }
}
