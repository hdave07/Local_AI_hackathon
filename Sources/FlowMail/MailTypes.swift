import FlowAX
import Foundation

/// Where a message lives. `account == nil` means a local "On My Mac" mailbox.
public struct MailboxRef: Sendable, Hashable, Codable, CustomStringConvertible {
    public let account: String?
    /// Slash-separated mailbox path, e.g. "Import/FlowTest" or "INBOX".
    public let path: String

    public init(account: String?, path: String) {
        self.account = account
        self.path = path
    }

    public var description: String { account.map { "\($0)/\(path)" } ?? "On My Mac/\(path)" }
}

/// Stable reference to one message (spec 02 §9 "bind activeMessage to stable ID").
/// `messageID` is the RFC 5322 Message-ID; `internalID` is Mail's scripting id,
/// stable while the message stays in `mailbox`.
public struct MailMessageRef: Sendable, Hashable, Codable {
    public let messageID: String
    public let mailbox: MailboxRef
    public let internalID: Int

    public init(messageID: String, mailbox: MailboxRef, internalID: Int) {
        self.messageID = messageID
        self.mailbox = mailbox
        self.internalID = internalID
    }
}

/// Visible metadata only: no headers beyond sender/subject/date, no recipients, no body.
public struct MailMessageSummary: Sendable, Equatable, Identifiable {
    public let ref: MailMessageRef
    public let senderName: String
    public let senderAddress: String
    public let subject: String
    public let dateReceived: Date?
    public let isRead: Bool

    public init(ref: MailMessageRef, senderName: String, senderAddress: String, subject: String, dateReceived: Date?, isRead: Bool) {
        self.ref = ref
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.subject = subject
        self.dateReceived = dateReceived
        self.isRead = isRead
    }

    public var id: MailMessageRef { ref }

    public var sender: String {
        if senderName.isEmpty { return senderAddress }
        return senderAddress.isEmpty ? senderName : "\(senderName) <\(senderAddress)>"
    }

    public var displayLine: String {
        var parts = [senderName.isEmpty ? senderAddress : senderName, subject.isEmpty ? "(no subject)" : subject]
        if let dateReceived { parts.append(Self.dateFormatter.string(from: dateReceived)) }
        return parts.joined(separator: " — ")
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM, j:mm")
        return f
    }()

    /// Splits Mail's "Name <address>" sender string.
    public static func splitSender(_ raw: String) -> (name: String, address: String) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let open = s.lastIndex(of: "<"), let close = s.lastIndex(of: ">"), open < close {
            var name = s[..<open].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
            return (name, String(s[s.index(after: open)..<close]))
        }
        return s.contains("@") ? ("", s) : (s, "")
    }
}

/// Search criteria. All given criteria must match (AND); each term may match subject or sender.
public struct MailQuery: Sendable, Equatable, Codable {
    public var sender: String?
    public var subject: String?
    public var terms: [String]
    /// Mailbox name or path to search; nil = Mail's unified Inbox.
    public var mailbox: String?
    public var limit: Int

    public init(sender: String? = nil, subject: String? = nil, terms: [String] = [], mailbox: String? = nil, limit: Int = 20) {
        self.sender = sender
        self.subject = subject
        self.terms = terms
        self.mailbox = mailbox
        self.limit = limit
    }

    public var isEmpty: Bool {
        (sender ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            && (subject ?? "").trimmingCharacters(in: .whitespaces).isEmpty && terms.isEmpty
    }

    public var description: String {
        var parts: [String] = []
        if let sender, !sender.isEmpty { parts.append("from “\(sender)”") }
        if let subject, !subject.isEmpty { parts.append("with subject “\(subject)”") }
        if !terms.isEmpty { parts.append("about “\(terms.joined(separator: " "))”") }
        parts.append("in \(mailbox.map { "mailbox “\($0)”" } ?? "Inbox")")
        return parts.joined(separator: " ")
    }
}

public struct MailSearchResult: Sendable, Equatable {
    public let messages: [MailMessageSummary]
    /// Total matches before the limit was applied.
    public let total: Int

    public init(messages: [MailMessageSummary], total: Int) {
        self.messages = messages
        self.total = total
    }
}

/// Message body prepared for reading aloud or display.
public struct MailMessageContent: Sendable, Equatable {
    public let summary: MailMessageSummary
    public let body: String
    public let truncated: Bool
}

public enum MailAvailability: Sendable, Equatable {
    case ready(accounts: Int)
    case notInstalled
    case notRunning
    case automationNotDetermined
    case automationDenied
    case noAccounts
}

/// What Flow observed in Mail's UI after opening (verification evidence).
public struct MailDisplayObservation: Sendable, Equatable {
    /// Mail's front window (via scripting) is titled with the subject.
    public let scriptedWindowMatches: Bool
    /// Accessibility shows a window titled with the subject.
    public let visibleWindowMatches: Bool
    /// Accessibility shows the start of the body text on screen.
    public let bodyVisible: Bool

    public init(scriptedWindowMatches: Bool, visibleWindowMatches: Bool, bodyVisible: Bool) {
        self.scriptedWindowMatches = scriptedWindowMatches
        self.visibleWindowMatches = visibleWindowMatches
        self.bodyVisible = bodyVisible
    }
}

public enum MailError: Error, Sendable, Equatable {
    case notInstalled
    case launchFailed
    case automationDenied
    case automationNotDetermined
    case noAccounts
    case mailboxNotFound(String)
    case ambiguousMailbox(String, paths: [String])
    case invalidQuery(String)
    case timedOut
    /// The referenced message no longer exists where it was (deleted, moved).
    case messageGone
    /// The message at the reference is not the one that was found earlier.
    case referenceChanged(String)
    case contentUnavailable
    case noActiveCandidates
    case numberOutOfRange(Int, count: Int)
    case noActiveMessage
    /// Scripting failed; only the numeric code is kept (stderr can contain message text).
    case scriptFailure(code: Int)
    /// Mail would address the reply to someone else (e.g. a Reply-To header, or extra Cc).
    case recipientMismatch(expected: String, actual: [String])
    /// A reply to this message is already open with different content; not duplicated.
    case draftAlreadyOpen
    /// The draft is no longer open in Mail (sent, saved and closed, or discarded by the user).
    case draftGone
    /// Several open drafts match; Flow will not guess which one is meant.
    case draftAmbiguous(Int)
    case noReplyAddress
    case emptyContent
    /// A draft id Flow did not create.
    case unknownDraft

    public var userMessage: String {
        switch self {
        case .notInstalled: "Apple Mail isn't installed."
        case .launchFailed: "Apple Mail couldn't be started."
        case .automationDenied:
            "Flow isn't allowed to use Mail. Turn it on in System Settings › Privacy & Security › Automation."
        case .automationNotDetermined: "Flow needs your permission to use Mail. Choose “Allow Mail access” and approve the prompt."
        case .noAccounts: "Mail has no accounts set up, so there's nothing to search."
        case .mailboxNotFound(let name): "There's no mailbox called “\(name)”."
        case .ambiguousMailbox(let name, let paths): "Several mailboxes are called “\(name)”: \(paths.joined(separator: ", ")). Use the full path."
        case .invalidQuery(let why): why
        case .timedOut: "Mail took too long to answer. Try a narrower search."
        case .messageGone: "That message isn't there any more (moved or deleted), so I didn't open it. Search again."
        case .referenceChanged(let what): "That message changed (\(what)), so I didn't open it. Search again."
        case .contentUnavailable: "Mail didn't provide readable text for this message."
        case .noActiveCandidates: "There's no list to choose from. Search first."
        case .numberOutOfRange(let n, let count): "There's no number \(n); choose 1 to \(count)."
        case .noActiveMessage: "No message is open in Flow yet. Open one first."
        case .scriptFailure(let code): "Mail reported an error (\(code))."
        case .recipientMismatch(let expected, let actual):
            "Mail would address this reply to \(actual.joined(separator: ", ")), not only \(expected), so I didn't create it."
        case .draftAlreadyOpen: "A reply to this message is already open. Review or close it first; I didn't create another."
        case .draftGone: "That draft isn't open in Mail any more."
        case .draftAmbiguous(let n): "\(n) open drafts look like this one, so I won't guess which to use."
        case .noReplyAddress: "That message has no sender address to reply to."
        case .emptyContent: "What should the reply say?"
        case .unknownDraft: "I don't know that draft."
        }
    }

    var status: NavigationStatus {
        switch self {
        case .notInstalled, .noAccounts, .contentUnavailable: .unsupported
        default: .failed
        }
    }

    public var retrySafe: Bool {
        switch self {
        case .timedOut, .scriptFailure: true
        default: false
        }
    }
}
