import FlowMail
@testable import FlowMailSend
import Foundation
import Testing

/// A scripted Mail: open drafts, Sent and Outbox. No real Mail.
@MainActor
final class ScriptedMail: MailSendTransport {
    var open: [OutgoingDraft]
    var returns: Bool? = true
    var lands: Landing = .sent
    var listError: MailError?
    var sendError: MailError?
    var beforeSend: (() -> Void)?
    private(set) var sendCalls = 0
    private(set) var sentSubjects: [String] = []
    private(set) var outboxSubjects: [String] = []
    enum Landing { case sent, outbox, nowhere, staysOpen }

    init(_ open: [OutgoingDraft]) { self.open = open }

    func outgoing(subject: String) async throws(MailError) -> [OutgoingDraft] {
        if let listError { throw listError }
        return open.filter { $0.subject == subject }
    }

    func send(subject: String, expected: OutgoingDraft) async throws(MailError) -> SendDispatch {
        beforeSend?()
        let m = open.filter { $0.subject == subject }
        guard m.count == 1 else { return .refused("count:\(m.count)") }
        guard m[0] == expected else { return .refused("changed") }
        sendCalls += 1
        if let sendError { throw sendError }
        switch lands {
        case .sent: open.removeAll { $0.subject == subject }; sentSubjects.append(subject)
        case .outbox: open.removeAll { $0.subject == subject }; outboxSubjects.append(subject)
        case .nowhere: open.removeAll { $0.subject == subject }
        case .staysOpen: break
        }
        return .dispatched(mailReturned: returns)
    }

    func evidence(subject: String, recipients: [String], since: Date) async throws(MailError) -> SendEvidence {
        SendEvidence(stillOpen: open.filter { $0.subject == subject }.count, inSent: sentSubjects.contains(subject),
                     inOutbox: outboxSubjects.contains(subject))
    }
}

@MainActor
@Suite("MailSender: at-most-once dispatch and outcome classification")
struct MailSenderTests {
    nonisolated static let subject = "Re: [FlowTest] Meeting tomorrow"
    nonisolated static let draft = OutgoingDraft(subject: subject, to: ["sarah.chen@example.invalid"], digest: "15:I can meet at 3", text: "I can meet at 3")
    nonisolated static func approved(_ id: UUID = UUID(), draftID: String = "d1") -> ApprovedSend {
        ApprovedSend(approvalID: id, draftID: draftID, subject: subject, recipients: ["Sarah.Chen@example.invalid"], version: 1,
                     contentHash: "h", body: "I can meet at 3")
    }

    func sender(_ mode: MailSendMode, _ mail: ScriptedMail, allow: Set<String>? = nil) -> MailSender {
        var c = MailSender.Configuration(recipientAllowlist: allow)
        c.evidenceTimeout = .milliseconds(20)
        c.pollInterval = .milliseconds(2)
        return MailSender(mode: mode, transport: mail, configuration: c)
    }

    @Test func disabledNeverTouchesMail() async {
        let mail = ScriptedMail([Self.draft])
        let out = await sender(.disabled, mail).send(Self.approved())
        #expect(out == .refused(.disabled, evidence: ["sending is disabled"]))
        #expect(mail.sendCalls == 0)
    }

    @Test func liveSendIsAcceptedOnlyWithSentEvidence() async {
        let mail = ScriptedMail([Self.draft])
        let s = sender(.live, mail)
        guard case .accepted(let queued, _) = await s.send(Self.approved()) else { Issue.record("not accepted"); return }
        #expect(!queued)
        #expect(mail.sendCalls == 1 && s.dispatchCount == 1)
    }

    @Test func outboxMeansQueuedNotSent() async {
        let mail = ScriptedMail([Self.draft]); mail.lands = .outbox
        guard case .accepted(let queued, _) = await sender(.live, mail).send(Self.approved()) else { Issue.record("not accepted"); return }
        #expect(queued)
    }

    @Test func aClosedWindowAloneIsUnknown() async {
        let mail = ScriptedMail([Self.draft]); mail.lands = .nowhere
        guard case .unknown = await sender(.live, mail).send(Self.approved()) else { Issue.record("expected unknown"); return }
    }

    @Test func errorAfterDispatchIsUnknownNeverNotSent() async {
        let mail = ScriptedMail([Self.draft]); mail.sendError = .timedOut
        guard case .unknown = await sender(.live, mail).send(Self.approved()) else { Issue.record("expected unknown"); return }
    }

    @Test func mailReportingFailureWithDraftStillOpenIsNotSent() async {
        let mail = ScriptedMail([Self.draft]); mail.returns = false; mail.lands = .staysOpen
        guard case .notSent = await sender(.live, mail).send(Self.approved()) else { Issue.record("expected notSent"); return }
    }

    @Test func sameDraftOrApprovalNeverDispatchesTwice() async {
        let mail = ScriptedMail([Self.draft]); mail.lands = .staysOpen  // even if the draft were still there
        let s = sender(.live, mail)
        let id = UUID()
        _ = await s.send(Self.approved(id))
        guard case .refused(.alreadyDispatched, _) = await s.send(Self.approved(id)) else { Issue.record("approval reused"); return }
        guard case .refused(.alreadyDispatched, _) = await s.send(Self.approved()) else { Issue.record("draft resent"); return }
        #expect(mail.sendCalls == 1)
    }

    @Test func unknownOutcomeIsNeverRetried() async {
        let mail = ScriptedMail([Self.draft]); mail.sendError = .timedOut
        let s = sender(.live, mail)
        _ = await s.send(Self.approved())
        mail.sendError = nil
        guard case .refused(.alreadyDispatched, _) = await s.send(Self.approved()) else { Issue.record("retried"); return }
        #expect(mail.sendCalls == 1)
    }

    @Test func confirmedNotSentMayBeRetriedOnlyWithANewApproval() async {
        let mail = ScriptedMail([Self.draft]); mail.returns = false; mail.lands = .staysOpen
        let s = sender(.live, mail)
        let first = UUID()
        _ = await s.send(Self.approved(first))
        guard case .refused(.alreadyDispatched, _) = await s.send(Self.approved(first)) else { Issue.record("approval reused"); return }
        mail.returns = true; mail.lands = .sent
        guard case .accepted = await s.send(Self.approved()) else { Issue.record("new approval refused"); return }
        #expect(mail.sendCalls == 2)
    }

    @Test(arguments: [
        OutgoingDraft(subject: subject, to: ["sarah.chen@example.invalid"], cc: ["boss@example.invalid"], digest: "x", text: "I can meet at 3"),
        OutgoingDraft(subject: subject, to: ["sarah.chen@example.invalid"], bcc: ["spy@example.invalid"], digest: "x", text: "I can meet at 3"),
        OutgoingDraft(subject: subject, to: ["sarah.chen@example.invalid", "team@example.invalid"], digest: "x", text: "I can meet at 3"),
        OutgoingDraft(subject: subject, to: ["sarah.okafor@example.invalid"], digest: "x", text: "I can meet at 3"),
    ])
    func extraOrDifferentRecipientsAreRefused(draft: OutgoingDraft) async {
        let mail = ScriptedMail([draft])
        guard case .refused(.recipientMismatch, _) = await sender(.live, mail).send(Self.approved()) else { Issue.record("sent"); return }
        #expect(mail.sendCalls == 0)
    }

    @Test func mailsTextMustMatchTheApprovedText() async {
        for text in ["I can meet at 4", nil] as [String?] {
            let mail = ScriptedMail([OutgoingDraft(subject: Self.subject, to: ["sarah.chen@example.invalid"], digest: "d", text: text)])
            guard case .refused(.contentChanged, _) = await sender(.live, mail).send(Self.approved()) else { Issue.record("sent \(String(describing: text))"); return }
            #expect(mail.sendCalls == 0)
        }
        // The quoted original and whitespace don't count.
        let quoted = "I can meet  at 3\n\nOn Fri, 13 Nov 2026, Sarah Chen wrote:\n> Can we meet?"
        let mail = ScriptedMail([OutgoingDraft(subject: Self.subject, to: ["sarah.chen@example.invalid"], digest: "d", text: quoted)])
        guard case .accepted = await sender(.live, mail).send(Self.approved()) else { Issue.record("refused"); return }
    }

    @Test func duplicateComposeWindowsAreRefused() async {
        let mail = ScriptedMail([Self.draft, Self.draft])
        guard case .refused(.ambiguousDraft(2), _) = await sender(.live, mail).send(Self.approved()) else { Issue.record("sent"); return }
        #expect(mail.sendCalls == 0)
    }

    @Test func lastMomentChangeInsideTheSendScriptIsRefused() async {
        let mail = ScriptedMail([Self.draft])
        mail.beforeSend = { mail.open = [OutgoingDraft(subject: Self.subject, to: ["sarah.chen@example.invalid"], digest: "16:I can meet at 4", text: "I can meet at 3")] }
        let s = sender(.live, mail)
        guard case .refused(.contentChanged, _) = await s.send(Self.approved()) else { Issue.record("sent"); return }
        #expect(mail.sendCalls == 0 && s.dispatchCount == 0)
    }

    @Test func liveAllowlistBlocksOtherRecipients() async {
        let mail = ScriptedMail([Self.draft])
        guard case .refused(.recipientNotAllowed, _) = await sender(.live, mail, allow: ["me@example.invalid"]).send(Self.approved())
        else { Issue.record("sent"); return }
        #expect(mail.sendCalls == 0)
    }

    @Test func dryRunRecordsExactlyOneAttemptAndNeverCallsSend() async {
        let mail = ScriptedMail([Self.draft])
        let s = sender(.dryRun, mail)
        guard case .rehearsed = await s.send(Self.approved()) else { Issue.record("not rehearsed"); return }
        guard case .refused(.alreadyDispatched, _) = await s.send(Self.approved()) else { Issue.record("rehearsed twice"); return }
        #expect(s.dryRunLog.count == 1)
        #expect(s.dryRunLog.first?.recipients == ["sarah.chen@example.invalid"])
        #expect(mail.sendCalls == 0 && s.dispatchCount == 0)
        #expect(mail.open.count == 1, "the draft is untouched")
    }

    @Test func dryRunStillRunsEveryCheck() async {
        let mail = ScriptedMail([OutgoingDraft(subject: Self.subject, to: ["sarah.chen@example.invalid"], cc: ["x@example.invalid"], digest: "x", text: "I can meet at 3")])
        let s = sender(.dryRun, mail)
        guard case .refused(.recipientMismatch, _) = await s.send(Self.approved()) else { Issue.record("rehearsed"); return }
        #expect(s.dryRunLog.isEmpty)
    }

    @Test func cancellationBeforeDispatchSendsNothing() async {
        let mail = ScriptedMail([Self.draft])
        let s = sender(.live, mail)
        let task = Task { @MainActor in await s.send(Self.approved()) }
        task.cancel()
        let out = await task.value
        if case .refused(.cancelled, _) = out {} else if case .accepted = out {} else { Issue.record("unexpected \(out)") }
        #expect(mail.sendCalls <= 1)
    }

    @Test func automationDeniedIsARefusal() async {
        let mail = ScriptedMail([Self.draft]); mail.listError = .automationDenied
        guard case .refused(.permissionDenied, _) = await sender(.live, mail).send(Self.approved()) else { Issue.record("x"); return }
    }

    @Test func scriptHasOnlyTheDocumentedOperations() {
        let s = JXAMailSendTransport.script
        #expect(s.contains("Mail.send(list[0])"))
        #expect(!s.contains(".delete(") && !s.contains("close(") && !s.contains("save"))
        #expect(s.components(separatedBy: "Mail.send(").count == 2, "exactly one send call site")
    }
}
