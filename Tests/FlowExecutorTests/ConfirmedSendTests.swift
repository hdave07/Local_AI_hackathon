import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowMail
import FlowMailSend
import FlowPlanner
import FlowRouting
import Foundation
import Synchronization
import Testing

/// T-023C: confirmed sending through the real TaskSession (router + planner) and real executor
/// over simulated Mail. No real Mail and no real sending.
@MainActor
@Suite("Confirmed sending: TaskSession + MacPlanExecutor + MailSender")
struct ConfirmedSendTests {
    /// Model double; by default it understands nothing.
    final class Model: TracedIntentClassifying {
        let answers: [String: Intent]
        init(_ answers: [String: Intent] = [:]) { self.answers = answers }
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            let intent = answers[utterance.lowercased()]
                ?? Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))
            return ClassificationTrace(outcome: .success(intent), attempts: [])
        }
    }

    final class Clock: Sendable {
        private let t = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        func now() -> Date { t.withLock { $0 } }
        func advance(_ s: TimeInterval) { t.withLock { $0 += s } }
    }

    @MainActor
    struct Flow {
        let rig: Rig
        let store: IntentRouter
        let session: TaskSession
        let clock = Clock()

        init(_ mode: MailSendMode? = .live, model: Model = Model()) {
            rig = Rig(drafting: true, sending: mode)
            store = IntentRouter(model: model)
            let clock = self.clock
            session = TaskSession(store: store, executor: rig.executor, now: { clock.now() })
        }

        var transport: FakeSendTransport { rig.sendTransport }
        var sender: MailSender { rig.sender! }

        /// "Find Sarah's email." → "The first one." → "Reply saying I can meet at 3:30."
        func draftReply() async -> Bool {
            guard case .awaitingChoice = await session.handle("Find Sarah's email.").state else { return false }
            guard case .completed = await session.handle("The first one.").state else { return false }
            guard case .completed = await session.handle("Reply saying I can meet at 3:30.").state else { return false }
            return await store.context.draft?.body == "I can meet at 3:30"
        }

        func askToSend(_ utterance: String = "Send that reply.") async -> SessionReply {
            await session.handle(utterance)
        }
    }

    // MARK: Acceptance

    @Test func acceptanceNeverMindCancelsAndNothingIsSent() async throws {
        let f = Flow(.live)
        #expect(await f.draftReply())
        let ask = await f.askToSend("Send that reply.")
        guard case .awaitingConfirmation(let request) = ask.state else { Issue.record("state \(ask.state) \(ask.say)"); return }
        let prompt = try #require(ask.say.last)
        #expect(prompt.contains("sarah.chen@example.invalid"), "names the verified recipient")
        #expect(prompt.contains("“I can meet at 3:30”"), "reads the complete verified body")
        #expect(prompt.contains("Re: [FlowTest] Meeting tomorrow"))
        #expect(request.draft == (await f.store.context.draft), "bound to the draft that was just re-read")
        #expect(f.rig.draftBackend.log.filter { $0 == "show" }.count >= 1, "the live draft was re-read and shown before asking")

        let cancel = await f.session.handle("Actually, never mind.")
        guard case .stopped(_, let reason) = cancel.state else { Issue.record("state \(cancel.state)"); return }
        #expect(reason == SendWording.declined)
        #expect(f.transport.sendCalls == 0 && f.sender.dispatchCount == 0)
        #expect(f.rig.draftBackend.open.count == 1, "the draft is still open, unsent")
        // A late "yes" after cancelling authorizes nothing.
        _ = await f.session.handle("Yes, send it.")
        #expect(f.transport.sendCalls == 0)
    }

    @Test func acceptanceDryRunRecordsExactlyOneAuthorizedAttempt() async throws {
        let f = Flow(.dryRun)
        #expect(await f.draftReply())
        guard case .awaitingConfirmation = await f.askToSend().state else { Issue.record("no confirmation"); return }
        let yes = await f.session.handle("Yes, send it.")
        guard case .completed = yes.state else { Issue.record("state \(yes.state) \(yes.say)"); return }
        #expect(yes.say.last?.contains("Nothing was sent") == true)
        #expect(f.sender.dryRunLog.count == 1)
        let record = try #require(f.sender.dryRunLog.first)
        let draft = try #require(await f.store.context.draft)
        #expect(record.draftID == draft.id && record.version == draft.version && record.contentHash == draft.contentHash)
        #expect(f.transport.sendCalls == 0, "Mail's Send was never called")
        #expect(f.rig.draftBackend.open.count == 1)
        // Saying it again does not produce a second attempt.
        _ = await f.session.handle("Send that reply.")
        _ = await f.session.handle("Yes, send it.")
        #expect(f.sender.dryRunLog.count == 1)
    }

    // MARK: Live mode over simulated Mail

    @Test func explicitYesSendsExactlyOnceAndNeverClaimsDelivery() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend("Can you send it?")
        let yes = await f.session.handle("Yes, send it.")
        guard case .completed = yes.state else { Issue.record("state \(yes.state) \(yes.say)"); return }
        #expect(f.transport.sendCalls == 1)
        #expect(f.transport.sent.first?.to == ["sarah.chen@example.invalid"])
        let said = yes.say.joined(separator: " ")
        #expect(said.contains("Sent mailbox") && said.contains("can't confirm delivery"))
        #expect(!said.lowercased().contains("delivered"))
        #expect(await f.store.context.draft == nil)
        let again = await f.session.handle("Send that email.")
        #expect(f.transport.sendCalls == 1, "a repeated command never sends a second copy")
        #expect(again.say.joined().contains("no draft") || again.say.joined().contains("There's no draft"))
    }

    @Test(arguments: ["sure", "okay", "go ahead", "ok go ahead", "send it", "Send that email.", "do it"])
    func vagueAssentOrRepeatedSendIsNotApproval(utterance: String) async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        let r = await f.session.handle(utterance)
        guard case .awaitingConfirmation = r.state else { Issue.record("state \(r.state) for \(utterance)"); return }
        #expect(r.say == [SendWording.reprompt])
        #expect(f.transport.sendCalls == 0)
        _ = await f.session.handle("yes")
        #expect(f.transport.sendCalls == 1, "exactly one send after the explicit yes")
    }

    @Test func readTheEmailBeforeSendingRepeatsTheDraftAndKeepsWaiting() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        let ask = await f.askToSend()
        let read = await f.session.handle("Read the email before sending.")
        guard case .awaitingConfirmation = read.state else { Issue.record("state \(read.state)"); return }
        #expect(read.say == [ask.say.last!])
        #expect(f.transport.sendCalls == 0)
    }

    @Test(arguments: ["No, don't send.", "no", "Cancel.", "stop", "not yet", "wait"])
    func declineOrCancelSendsNothing(utterance: String) async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        let r = await f.session.handle(utterance)
        #expect(!r.state.isPaused, "\(utterance) left the confirmation open")
        _ = await f.session.handle("yes")
        #expect(f.transport.sendCalls == 0)
        #expect(f.rig.draftBackend.open.count == 1)
    }

    @Test func confirmationExpires() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.clock.advance(Approval.lifetime + 1)
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason == SendWording.expired)
        #expect(f.transport.sendCalls == 0)
    }

    @Test func editAfterTheQuestionInvalidatesTheApproval() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.rig.draftBackend.open[0].body = "I can meet at 4:30"  // edited in Mail (or by FlowText) before "yes"
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("nothing was sent"))
        #expect(f.transport.sendCalls == 0)
        #expect(await f.store.context.reviewedDraftVersion == nil, "the edited draft must be reviewed again")
        // Asking again shows the new text and needs a new yes.
        let again = await f.askToSend()
        #expect(again.say.last?.contains("I can meet at 4:30") == true)
        _ = await f.session.handle("yes")
        #expect(f.transport.sent.first?.body == "I can meet at 4:30")
        #expect(f.transport.sendCalls == 1)
    }

    @Test func sameLookingEditIsStillDetected() async {
        // Same window title, same recipient, same Message-ID context: only the body differs by one character.
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.rig.draftBackend.open[0].body = "I can meet at 3:30."
        _ = await f.session.handle("yes")
        #expect(f.transport.sendCalls == 0)
    }

    @Test func editBetweenApprovalAndDispatchIsRefused() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.transport.beforeSend = { f.rig.draftBackend.open[0].body = "Changed at the last moment" }
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("nothing was sent") || reason.contains("Nothing was sent"))
        #expect(f.transport.sendCalls == 0)
    }

    @Test func addedCcOrBccBlocksTheSend() async {
        for field in ["cc", "bcc"] {
            let f = Flow(.live)
            #expect(await f.draftReply())
            _ = await f.askToSend()
            if field == "cc" { f.rig.draftBackend.open[0].cc = ["boss@example.invalid"] } else { f.rig.draftBackend.open[0].bcc = ["x@example.invalid"] }
            _ = await f.session.handle("yes")
            #expect(f.transport.sendCalls == 0, "\(field) was added silently")
        }
    }

    @Test func duplicateComposeWindowsBlockTheSend() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.rig.draftBackend.open.append(f.rig.draftBackend.open[0])
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("2 drafts"))
        #expect(f.transport.sendCalls == 0)
    }

    @Test func unknownOutcomeIsReportedAndNeverRetried() async {
        for behavior in [FakeSendTransport.Behavior.throwsAfterSend, .closesSilently] {
            let f = Flow(.live)
            #expect(await f.draftReply())
            _ = await f.askToSend()
            f.transport.behavior = behavior
            let r = await f.session.handle("yes")
            guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
            #expect(reason.contains("couldn't confirm"))
            #expect(!r.say.joined().contains("Sent mailbox"))
            f.transport.behavior = .sends
            let again = await f.session.handle("Send that reply.")
            if case .awaitingConfirmation = again.state { _ = await f.session.handle("yes") }
            #expect(f.transport.sendCalls == 1, "\(behavior): never a second send after an unknown outcome")
        }
    }

    @Test func mailReportedFailureIsNotSentAndSaysSo() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.transport.behavior = .returnsFalse
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("couldn't send") && reason.contains("still open"))
    }

    @Test func outboxIsReportedAsQueued() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        f.transport.behavior = .queues
        let r = await f.session.handle("yes")
        #expect(r.say.joined().contains("Outbox"))
        #expect(!r.say.joined().contains("Mail sent it"))
    }

    @Test func disabledByDefault() async {
        let f = Flow(nil)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        let r = await f.session.handle("yes")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("disabled"))
        #expect(f.transport.sendCalls == 0)
    }

    // MARK: Bypass attempts

    @Test func modelCannotSendWithoutTheWordSendOrAConfirmation() async {
        let model = Model([
            "yes please do it": Intent(kind: .direct, action: .requestSend, summary: "m", source: .model(id: "bonsai")),
            "fire it off to her": Intent(kind: .direct, action: .requestSend, summary: "m", source: .model(id: "bonsai")),
        ])
        let f = Flow(.live, model: model)
        #expect(await f.draftReply())
        for u in ["yes please do it", "fire it off to her"] {
            let r = await f.session.handle(u)
            if case .awaitingConfirmation = r.state { Issue.record("\(u) reached confirmation") }
        }
        #expect(f.transport.sendCalls == 0)
    }

    @Test func dictatedSendIsContentNotACommand() async {
        let f = Flow(.live)
        guard case .awaitingChoice = await f.session.handle("Find Sarah's email.").state else { Issue.record("x"); return }
        _ = await f.session.handle("The first one.")
        let r = await f.session.handle("Reply saying I'll send it tomorrow, yes send it")
        if case .awaitingConfirmation = r.state { Issue.record("dictation reached a send confirmation") }
        #expect(f.transport.sendCalls == 0)
    }

    @Test func flowsOwnPromptEchoedBackNeverApproves() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        let ask = await f.askToSend()
        _ = await f.session.handle(ask.say.last!)
        #expect(f.transport.sendCalls == 0)
        #expect(ConfirmationReply.parse(ask.say.last!) != .approve)
    }

    @Test func sendMyReplyToSomeoneElseIsRefused() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        let wrong = await f.session.handle("Send my reply to Priya.")
        if case .awaitingConfirmation = wrong.state { Issue.record("wrong recipient reached confirmation") }
        #expect(wrong.say.joined().contains("not Priya"))
        let right = await f.session.handle("Send my reply to Sarah.")
        guard case .awaitingConfirmation = right.state else { Issue.record("state \(right.state) \(right.say)"); return }
    }

    // MARK: Executor-level guarantees

    @Test func retriedExecutorCallAndCrossDraftApprovalAreRefused() async throws {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()  // refreshes and presents; context now holds the live draft
        let draft = try #require(await f.store.context.draft)
        let approval = Approval(action: .send, draft: draft, issuedAt: Date())
        let plan = UUID()
        func send(_ d: DraftSnapshot, _ a: Approval, attempt: Int) async -> ExecutionResult {
            await f.rig.executor.execute(ExecutionRequest(planID: plan, stepID: 9, attempt: attempt, action: .requestSend, channel: .mail,
                                                          bindings: StepBindings(draft: d, approval: a), expectation: .sent))
        }
        // An approval for another draft never authorizes this one.
        let other = DraftSnapshot(id: "other", recipients: ["sarah.okafor@example.invalid"], subject: "Re: x", body: "hi", version: 1)
        let cross = await send(draft, Approval(action: .send, draft: other, issuedAt: Date()), attempt: 1)
        #expect(cross.error == .approvalInvalid)
        #expect(f.transport.sendCalls == 0)
        let first = await send(draft, approval, attempt: 1)
        #expect(first.status == .completed)
        let retry = await send(draft, approval, attempt: 2)
        #expect(retry.status != .completed)
        #expect(f.transport.sendCalls == 1)
    }

    @Test func noApprovalNoSend() async throws {
        let f = Flow(.live)
        #expect(await f.draftReply())
        let draft = try #require(await f.store.context.draft)
        let r = await f.rig.executor.execute(ExecutionRequest(planID: UUID(), stepID: 1, attempt: 1, action: .requestSend, channel: .mail,
                                                               bindings: StepBindings(draft: draft), expectation: .sent))
        #expect(r.error == .approvalInvalid)
        #expect(f.transport.sendCalls == 0)
    }

    @Test func stopWhileTheConfirmationIsOpenCancelsIt() async {
        let f = Flow(.live)
        #expect(await f.draftReply())
        _ = await f.askToSend()
        _ = await f.session.handle("stop")
        #expect(await f.session.runner.currentApproval == nil)
        _ = await f.session.handle("yes")
        #expect(f.transport.sendCalls == 0)
    }
}
