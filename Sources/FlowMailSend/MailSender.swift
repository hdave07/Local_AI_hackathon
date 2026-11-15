import FlowMail
import Foundation

// T-023C: explicitly confirmed Apple Mail sending (ADR 0010). This module only *dispatches*
// an already-approved draft and classifies what happened. Approval, the live Accessibility
// re-read of the draft and the at-most-once ledger live in FlowPlanner / FlowExecutor.

/// Whether Flow may press Send. Real sending is off unless explicitly enabled.
public enum MailSendMode: String, Sendable, Equatable {
    /// `request_send` is unsupported; nothing is inspected or sent.
    case disabled
    /// Every check runs against the real draft; the send is recorded, never performed.
    case dryRun = "dry_run"
    /// Mail's `send` command is called once for an approved, re-verified draft.
    case live
}

/// An open, unsent Mail draft as Mail's scripting interface reports it.
public struct OutgoingDraft: Sendable, Equatable, Codable {
    public let subject: String
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]
    /// Length and hash of Mail's scripted content (change detection between two script calls).
    public let digest: String

    public init(subject: String, to: [String], cc: [String] = [], bcc: [String] = [], digest: String) {
        self.subject = subject
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.digest = digest
    }
}

/// What the one dispatching script call did.
public enum SendDispatch: Sendable, Equatable {
    /// The script re-checked the draft and refused before calling `send` (nothing sent).
    case refused(String)
    /// `send` was called. `mailReturned` is Mail's boolean, or nil if the call raised.
    case dispatched(mailReturned: Bool?)
}

/// Read-only evidence after a send: is the draft still open, and is a matching message in
/// the Sent mailbox or the Outbox. Neither proves delivery to the recipient.
public struct SendEvidence: Sendable, Equatable {
    public let stillOpen: Int
    public let inSent: Bool
    public let inOutbox: Bool

    public init(stillOpen: Int, inSent: Bool, inOutbox: Bool) {
        self.stillOpen = stillOpen
        self.inSent = inSent
        self.inOutbox = inOutbox
    }
}

/// Mail operations used for sending. `send` must re-check recipients and content inside the
/// same call that sends, so nothing can change between the check and the send.
@MainActor
public protocol MailSendTransport: AnyObject {
    func outgoing(subject: String) async throws(MailError) -> [OutgoingDraft]
    func send(subject: String, expected: OutgoingDraft) async throws(MailError) -> SendDispatch
    func evidence(subject: String, recipients: [String], since: Date) async throws(MailError) -> SendEvidence
}

/// The draft state the user approved, after the executor re-read it live and matched the approval.
public struct ApprovedSend: Sendable, Equatable {
    public let approvalID: UUID
    public let draftID: String
    public let subject: String
    public let recipients: [String]
    public let version: Int
    public let contentHash: String

    public init(approvalID: UUID, draftID: String, subject: String, recipients: [String], version: Int, contentHash: String) {
        self.approvalID = approvalID
        self.draftID = draftID
        self.subject = subject
        self.recipients = recipients
        self.version = version
        self.contentHash = contentHash
    }
}

public enum SendRefusal: Sendable, Equatable {
    case disabled
    case alreadyDispatched
    case ambiguousDraft(Int)
    case draftGone
    case recipientMismatch
    case recipientNotAllowed
    case contentChanged
    case permissionDenied
    case mailUnavailable
    case cancelled
}

/// What happened. Only `accepted` means Mail took the message; nothing here means delivered.
public enum SendOutcome: Sendable, Equatable {
    /// Mail accepted it: found in Sent (`queued == false`) or still in the Outbox (`queued == true`).
    case accepted(queued: Bool, evidence: [String])
    /// Dry run: every check passed and one send was recorded, not performed.
    case rehearsed(evidence: [String])
    /// Nothing was dispatched.
    case refused(SendRefusal, evidence: [String])
    /// Dispatched; Mail reported failure and the draft is still open. Not retried automatically.
    case notSent(evidence: [String])
    /// Dispatched; the result could not be established. Never retried automatically.
    case unknown(evidence: [String])
}

public struct DryRunRecord: Sendable, Equatable {
    public let approvalID: UUID
    public let draftID: String
    public let subject: String
    public let recipients: [String]
    public let version: Int
    public let contentHash: String
    public let at: Date
}

/// Dispatches approved drafts at most once (per draft and per approval) and classifies the outcome.
@MainActor
public final class MailSender {
    public struct Configuration: Sendable {
        /// How long to look for the sent message in Sent / Outbox after dispatching.
        public var evidenceTimeout: Duration = .seconds(30)
        public var pollInterval: Duration = .milliseconds(500)
        /// Live mode only: when set, every recipient must be listed here (lowercased addresses).
        public var recipientAllowlist: Set<String>?
        public init(recipientAllowlist: Set<String>? = nil) { self.recipientAllowlist = recipientAllowlist }
    }

    public let mode: MailSendMode
    let transport: MailSendTransport
    let configuration: Configuration
    let now: @Sendable () -> Date

    /// Every draft and approval that reached the dispatch point, with its outcome.
    public private(set) var dispatchedDrafts: [String: SendOutcome] = [:]
    private var usedApprovals: Set<UUID> = []
    /// Dry-run mode: the sends that would have happened.
    public private(set) var dryRunLog: [DryRunRecord] = []
    /// Live mode: how many times Mail's `send` was called (tests and evidence).
    public private(set) var dispatchCount = 0

    public init(mode: MailSendMode, transport: MailSendTransport, configuration: Configuration = Configuration(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.mode = mode
        self.transport = transport
        self.configuration = configuration
        self.now = now
    }

    public func send(_ approved: ApprovedSend) async -> SendOutcome {
        guard mode != .disabled else { return .refused(.disabled, evidence: ["sending is disabled"]) }
        // At most once: a draft that already reached dispatch, or a used approval, is never sent again.
        // A send Mail explicitly reported as failed (draft still open) may be retried only with a new approval.
        if usedApprovals.contains(approved.approvalID) {
            return .refused(.alreadyDispatched, evidence: ["this approval was already used"])
        }
        if let previous = dispatchedDrafts[approved.draftID] {
            if case .notSent = previous {} else {
                return .refused(.alreadyDispatched, evidence: ["draft \(approved.draftID.suffix(8)) already reached dispatch"])
            }
        }
        if Task.isCancelled { return .refused(.cancelled, evidence: ["cancelled before checking Mail"]) }

        let open: [OutgoingDraft]
        do throws(MailError) {
            open = try await transport.outgoing(subject: approved.subject)
        } catch {
            return .refused(Self.refusal(error), evidence: ["listing open drafts failed: \(error)"])
        }
        guard !open.isEmpty else { return .refused(.draftGone, evidence: ["no open draft with this subject"]) }
        guard open.count == 1, let draft = open.first else {
            return .refused(.ambiguousDraft(open.count), evidence: ["\(open.count) open drafts with this subject"])
        }
        // Exactly the approved recipients; never an added Cc, Bcc or reply-all address.
        let approvedTo = Self.normalized(approved.recipients)
        guard Self.normalized(draft.to) == approvedTo, draft.cc.isEmpty, draft.bcc.isEmpty else {
            return .refused(.recipientMismatch, evidence: [
                "Mail's draft: To \(draft.to.count), Cc \(draft.cc.count), Bcc \(draft.bcc.count); approved To \(approvedTo.count)",
            ])
        }
        if mode == .live, let allow = configuration.recipientAllowlist, !approvedTo.allSatisfy(allow.contains) {
            return .refused(.recipientNotAllowed, evidence: ["a recipient is not on the live-test allowlist"])
        }
        let checked = ["one open draft with this subject", "To matches the approval exactly; no Cc or Bcc"]
        if Task.isCancelled { return .refused(.cancelled, evidence: checked + ["cancelled before sending"]) }

        // Claim the draft and the approval *before* dispatching: a concurrent or retried request is refused.
        usedApprovals.insert(approved.approvalID)

        if mode == .dryRun {
            dryRunLog.append(DryRunRecord(approvalID: approved.approvalID, draftID: approved.draftID, subject: approved.subject,
                                          recipients: approvedTo, version: approved.version, contentHash: approved.contentHash,
                                          at: now()))
            let outcome = SendOutcome.rehearsed(evidence: checked + ["dry run: Mail's Send was not called"])
            dispatchedDrafts[approved.draftID] = outcome
            return outcome
        }

        dispatchedDrafts[approved.draftID] = .unknown(evidence: ["dispatch in progress"])
        let since = now().addingTimeInterval(-60)
        let dispatch: SendDispatch
        do throws(MailError) {
            dispatchCount += 1
            dispatch = try await transport.send(subject: approved.subject, expected: draft)
        } catch {
            // The script may have reached `send`: the outcome is unknown, never "not sent".
            return finish(approved, .unknown(evidence: checked + ["the send request failed (\(error)); Mail may have sent it"]))
        }

        switch dispatch {
        case .refused(let why):
            // Re-checked inside the sending script: something changed, nothing was sent.
            dispatchCount -= 1
            dispatchedDrafts[approved.draftID] = nil
            return .refused(why.hasPrefix("count:") ? .ambiguousDraft(Int(why.dropFirst(6)) ?? 0) : .contentChanged,
                            evidence: checked + ["Mail's draft changed just before sending (\(why)); not sent"])
        case .dispatched(let returned):
            let evidence = await collectEvidence(approved, since: since)
            var notes = checked + ["Mail's send returned \(returned.map { String($0) } ?? "an error")"]
            guard let e = evidence else {
                return finish(approved, .unknown(evidence: notes + ["couldn't read Sent or Outbox afterwards"]))
            }
            notes.append("afterwards: open drafts \(e.stillOpen), in Sent \(e.inSent), in Outbox \(e.inOutbox)")
            if e.inSent { return finish(approved, .accepted(queued: false, evidence: notes)) }
            if e.inOutbox { return finish(approved, .accepted(queued: true, evidence: notes)) }
            if returned == false, e.stillOpen == 1 { return finish(approved, .notSent(evidence: notes)) }
            // A closed compose window alone is not evidence of sending.
            return finish(approved, .unknown(evidence: notes))
        }
    }

    private func collectEvidence(_ approved: ApprovedSend, since: Date) async -> SendEvidence? {
        let deadline = ContinuousClock.now + configuration.evidenceTimeout
        var last: SendEvidence?
        repeat {
            if let e = try? await transport.evidence(subject: approved.subject, recipients: Self.normalized(approved.recipients),
                                                     since: since) {
                last = e
                if e.inSent { return e }
            }
            try? await Task.sleep(for: configuration.pollInterval)
        } while ContinuousClock.now < deadline
        return last
    }

    private func finish(_ approved: ApprovedSend, _ outcome: SendOutcome) -> SendOutcome {
        dispatchedDrafts[approved.draftID] = outcome
        return outcome
    }

    static func normalized(_ addresses: [String]) -> [String] {
        addresses.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted()
    }

    static func refusal(_ error: MailError) -> SendRefusal {
        switch error {
        case .automationDenied, .automationNotDetermined: .permissionDenied
        default: .mailUnavailable
        }
    }
}
