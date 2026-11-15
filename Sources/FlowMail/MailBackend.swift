import Foundation

/// Narrow, read-only interface to Apple Mail so controller logic is testable.
/// There is deliberately no API to send, delete, move, flag or mark messages.
@MainActor
public protocol MailBackend: AnyObject {
    /// Checks installation, launch state, Automation consent and accounts.
    /// `requestPermission` lets macOS show its consent prompt (never bypassed).
    func availability(requestPermission: Bool) async -> MailAvailability
    func search(_ query: MailQuery) async throws(MailError) -> MailSearchResult
    /// Re-reads the message at `ref`. Throws `.messageGone` if it no longer exists there.
    func lookup(_ ref: MailMessageRef) async throws(MailError) -> MailMessageSummary
    /// `lookup` plus the plain-text body in one round trip (revalidation before opening).
    func lookupWithContent(_ ref: MailMessageRef) async throws(MailError) -> (MailMessageSummary, String)
    /// Opens the message in its own Mail window and brings Mail forward.
    func open(_ ref: MailMessageRef, expectedSubject: String) async throws(MailError) -> MailOpenOutcome
    /// Plain-text body as Mail renders it.
    func content(_ ref: MailMessageRef) async throws(MailError) -> String
}

/// Observes what Mail actually shows (FlowAX).
@MainActor
public protocol MailDisplayVerifying: AnyObject {
    func observe(subject: String, bodySnippet: String?) async -> (windowMatches: Bool, bodyVisible: Bool)
}

/// What Mail reported right after opening.
public struct MailOpenOutcome: Sendable, Equatable {
    /// Name of Mail's front window (verification evidence).
    public let frontWindow: String?
    /// Read flag after opening (Mail may mark messages read when shown).
    public let isReadAfter: Bool?

    public init(frontWindow: String?, isReadAfter: Bool?) {
        self.frontWindow = frontWindow
        self.isReadAfter = isReadAfter
    }
}
