import FlowCore
@testable import FlowPlanner
import FlowLLM
import FlowRouting
import Foundation
import Testing

@Suite("Acceptance: find → choose → reply → review, never send without confirmation")
struct AcceptanceTests {
    @Test func fullWorkflow() async throws {
        let h = Harness()

        // 1. Plan and run until the ambiguous search pauses the plan.
        let first = await h.say(Fixture.acceptance)
        let plan = try #require(first.plan)
        #expect(plan.steps.map(\.capability) == [.activate, .findMessage, .compose, .review])
        #expect(plan.steps.map(\.origin) == [.implied, .spoken, .spoken, .spoken])
        #expect(plan.steps[2].dependsOn == [1] && plan.steps[3].dependsOn == [2])
        #expect(plan.steps[2].repliesToSelectedMessage)
        #expect(plan.steps.allSatisfy { !$0.requiresConfirmation })
        let question = try #require(await h.state.question)
        #expect(question.candidates.map(\.id) == ["m1", "m2"])
        #expect(first.say.joined().contains("Sarah Chen") && first.say.joined().contains("Sarah Patel"))
        #expect(await h.requests.contains { Capability($0.action) == .compose } == false)

        // 2. The user resolves the ambiguity; the plan resumes and finishes at review.
        let second = await h.say("the first one")
        #expect(await h.state.isCompleted)
        let ctx = await h.context
        #expect(ctx.selectedMessage?.id == "m1")
        let draft = try #require(ctx.draft)
        #expect(draft.recipients == ["sarah.chen@example.com"])
        #expect(draft.body == "I can meet at 3")
        #expect(draft.inReplyTo == "m1")
        #expect(ctx.reviewedDraftVersion == draft.version)
        #expect(second.say.joined().contains("Here's the draft"))
        #expect(await h.mock.sendRequests.isEmpty)

        // 3. "send it" asks for explicit confirmation bound to recipient and content.
        let ask = await h.say("send it")
        let request = try #require(await h.state.approvalRequest)
        #expect(request.draft == draft)
        #expect(ask.say.joined().contains("sarah.chen@example.com") && ask.say.joined().contains("I can meet at 3"))
        #expect(await h.mock.sendRequests.isEmpty)

        // 4. Only an explicit yes sends, exactly once.
        _ = await h.say("yes")
        #expect(await h.state.isCompleted)
        #expect(await h.mock.world.sent.count == 1)
        #expect(await h.context.draft == nil)
    }

    @Test func choosingBySenderNameWorks() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        _ = await h.say("Sarah Patel")
        #expect(await h.context.selectedMessage?.id == "m2")
        #expect(await h.context.draft?.recipients == ["sarah.p@example.com"])
    }

    @Test func tiedAnswerIsAskedAgainNotGuessed() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        let r = await h.say("Sarah")
        #expect(await h.state.question != nil)
        #expect(r.say.joined().contains("which one"))
        #expect(await h.requests.contains { Capability($0.action) == .compose } == false)
    }
}

@Suite("Channel-agnostic planning")
struct ChannelTests {
    func planOf(_ s: String, _ ctx: ConversationContext = .empty) async throws -> Plan {
        let planner = TaskPlanner(router: IntentRouterCore(model: NoModel()))
        guard case .plan(let p) = await planner.plan(s, context: ctx) else { throw PlanError.notPlanned }
        return p
    }
    enum PlanError: Error { case notPlanned }

    @Test func textMessageHasNoMailSteps() async throws {
        let p = try await planOf("text Lee I'm running late")
        #expect(p.steps.count == 1)
        #expect(p.steps[0].channel == .messages)
        #expect(p.steps[0].action == .createDraft(recipient: "Lee", content: "I'm running late"))
    }

    @Test(arguments: [
        ("send Lee a whatsapp saying I'm on my way", MessageChannel.whatsapp, "I'm on my way"),
        ("message Lee on WhatsApp saying I'm on my way", .whatsapp, "I'm on my way"),
        ("email Dana saying the report is ready", .mail, "the report is ready"),
        ("tell Dana by text that I'm outside", .messages, "I'm outside"),
    ])
    func spokenChannelIsResolved(utterance: String, channel: MessageChannel, content: String) async throws {
        let p = try await planOf(utterance)
        let compose = try #require(p.steps.first { $0.capability == .compose })
        #expect(compose.channel == channel)
        guard case .createDraft(_, let c) = compose.action else { Issue.record("not a draft"); return }
        #expect(c == content)
        // Only Mail has an allowlisted app to activate; other adapters prepare their own.
        #expect(p.steps.contains { $0.action == .activateApp(.mail) } == (channel == .mail))
    }

    @Test func whatsappReplyStaysOnWhatsapp() async throws {
        let h = Harness()
        _ = await h.say("find Lee's whatsapp message, reply saying see you soon, and show it to me")
        #expect(await h.state.isCompleted)
        let draft = try #require(await h.context.draft)
        #expect(draft.channel == .whatsapp)
        #expect(draft.recipients == ["+1 555 0100"])
        #expect(draft.body == "see you soon")
        #expect(await h.requests.allSatisfy { $0.action != .activateApp(.mail) })
        let ask = await h.say("send it")
        #expect(ask.say.joined().contains("by whatsapp"))
    }

    @Test func approvalIsBoundToTheChannel() {
        let mail = DraftSnapshot(channel: .mail, id: "d", recipients: ["lee"], body: "hi", version: 1)
        let chat = DraftSnapshot(channel: .whatsapp, id: "d", recipients: ["lee"], body: "hi", version: 1)
        #expect(mail.contentHash != chat.contentHash)
        let approval = Approval(action: .send, draft: mail, issuedAt: Date())
        #expect(approval.authorizes(.send, on: mail, now: Date()))
        #expect(!approval.authorizes(.send, on: chat, now: Date()))
    }

    @Test func customChannelNeedsNoPlannerChange() async throws {
        let signal = MessageChannel(rawValue: "signal")
        let catalog = ChannelCatalog(
            channels: ChannelCatalog.standard.channels + [ChannelInfo(channel: signal, displayName: "Signal", app: nil, spokenNames: ["signal"])],
            defaultChannel: .mail)
        let planner = TaskPlanner(router: IntentRouterCore(model: NoModel()), catalog: catalog)
        guard case .plan(let p) = await planner.plan("message Lee on signal saying hi", context: .empty) else {
            Issue.record("not planned"); return
        }
        #expect(p.steps.first?.channel == signal)
    }
}

@Suite("Plan structure and bounds")
struct PlanStructureTests {
    @Test(arguments: [
        ("put mail and calendar side by side", 1),
        ("reply to sarah saying thanks and see you then", 1),
        ("tell lee I'll call and send the notes", 1),
        (Fixture.acceptance, 3),
        ("open notes then scroll down", 2),
        ("find the email from priya and reply saying paid", 2),
    ])
    func clauseSplitting(utterance: String, count: Int) {
        #expect(TaskPlanner.clauses(utterance).count == count, "\(TaskPlanner.clauses(utterance))")
    }

    @Test func tooManyStepsAsks() async throws {
        let h = Harness()
        let r = await h.say("open notes, open mail, open safari, open finder, open calendar, scroll down")
        #expect(r.plan == nil)
        #expect(r.say.joined().contains("more than 5"))
        #expect(await h.requests.isEmpty)
    }

    @Test func sendInsertsReviewAndConfirmation() async throws {
        let planner = TaskPlanner(router: IntentRouterCore(model: NoModel()))
        guard case .plan(let p) = await planner.plan("email Dana saying hi, then send it", context: .empty) else {
            Issue.record("not planned"); return
        }
        #expect(p.steps.map(\.capability) == [.activate, .compose, .review, .send])
        #expect(p.steps[2].origin == .implied)
        #expect(p.steps[3].requiresConfirmation)
        #expect(p.steps[3].failurePolicy == .neverRetry)
        #expect(p.risk == .external)
    }

    @Test func declinedActionsExecuteNothing() async throws {
        let h = Harness()
        let r = await h.say("delete the email from priya")
        #expect(r.plan == nil)
        #expect(await h.requests.isEmpty)
    }

    @Test func singleCommandIsAOneStepPlan() async throws {
        let h = Harness()
        let r = await h.say("open notes")
        #expect(r.plan?.steps.count == 1)
        #expect(await h.state.isCompleted)
        #expect(await h.context.activeApp == .notes)
    }

    @Test func routerFollowUpStillWorks() async throws {
        let h = Harness()
        let q = await h.say("open it")
        #expect(q.say.joined().contains("Which app"))
        _ = await h.say("Safari")
        #expect(await h.mock.world.activeApp == .safari)
    }
}

@Suite("Ambiguity, stale state and preconditions")
struct StateTests {
    @Test func staleCandidatesAreSearchedAgainNotTrusted() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        await h.mock.bumpEpoch()  // mailbox changed while the user was deciding
        let r = await h.say("the first one")
        // The stale pick is rejected, the search re-runs once, and the user is asked again.
        #expect(await h.state.question != nil)
        #expect(r.say.joined().contains("Which one"))
        let reads = await h.requests.filter { Capability($0.action) == .findMessage }
        #expect(reads.count == 3)  // search, stale pick, fresh search
    }

    @Test func oldQuestionIsRefreshed() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        h.clock.advance(PlanRunner.questionLifetime + 1)
        let r = await h.say("the first one")
        #expect(r.say.joined().contains("out of date"))
        #expect(await h.state.question != nil)
    }

    @Test func replyWithoutAMessageAsksFirst() async throws {
        let h = Harness()
        let r = await h.say("draft a reply saying ok")
        #expect(r.plan == nil)
        #expect(await h.requests.isEmpty)
    }

    @Test func sendWithoutADraftStops() async throws {
        let h = Harness()
        let r = await h.say("send it")
        #expect(r.state.stopReason != nil)
        #expect(await h.mock.sendRequests.isEmpty)
    }

    @Test func pendingQuestionIsMirroredInTaskContext() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        guard case .plan(_, let options) = await h.context.pending else { Issue.record("no pending plan question"); return }
        #expect(options.count == 2)
        _ = await h.say("the first one")
        #expect(await h.context.pending == nil)
    }
}

@Suite("Cancellation")
struct CancellationTests {
    @Test func stopInterruptsTheRunningStepAndPreventsLaterSteps() async throws {
        let h = Harness()
        await h.mock.delay(.activate, by: .seconds(2))
        let run = Task { await h.say("open mail, then scroll down, then open notes") }
        try await Task.sleep(for: .milliseconds(100))
        let stop = await h.say("stop")
        #expect(stop.say.contains("Stopped."))
        _ = await run.value
        #expect(await h.state.isCancelled)
        let actions = await h.requests.map(\.action)
        #expect(actions == [.activateApp(.mail)])  // nothing after the interrupted step
    }

    @Test func cancelWhilePausedDropsTheQuestion() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        _ = await h.say("cancel")
        #expect(await h.state.isCancelled)
        #expect(await h.context.pending == nil)
        _ = await h.say("the first one")
        #expect(await h.requests.contains { Capability($0.action) == .compose } == false)
    }

    @Test func cancelDuringConfirmationSendsNothing() async throws {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        _ = await h.say("the first one")
        _ = await h.say("send it")
        _ = await h.say("stop")
        _ = await h.say("yes")  // too late: the confirmation was cancelled
        #expect(await h.mock.sendRequests.isEmpty)
    }
}

@Suite("Failures and bounded retries")
struct FailureTests {
    @Test func retrySafeLowRiskStepIsRetriedOnce() async throws {
        let h = Harness()
        await h.mock.inject([ExecutionResult(status: .failed, error: .timeout, retrySafe: true, userMessage: "slow")], for: .activate)
        _ = await h.say("open notes")
        #expect(await h.state.isCompleted)
        #expect(await h.requests.count == 2)
    }

    @Test func retriesAreBounded() async throws {
        let h = Harness()
        let fail = ExecutionResult(status: .failed, error: .timeout, retrySafe: true, userMessage: "Notes didn't open.")
        await h.mock.inject([fail, fail, fail], for: .activate)
        let r = await h.say("open notes")
        #expect(r.state.stopReason == "Notes didn't open.")
        #expect(await h.requests.count == 2)
    }

    @Test func notRetrySafeStopsImmediately() async throws {
        let h = Harness()
        await h.mock.inject([ExecutionResult(status: .failed, error: .permissionDenied, retrySafe: false, userMessage: "No access.")], for: .activate)
        _ = await h.say("open notes, then scroll down")
        #expect(await h.requests.count == 1)
        #expect(await h.state.stopReason == "No access.")
    }

    @Test func contentStepsAreNotRetriedAutomatically() async throws {
        let h = Harness()
        await h.mock.inject([ExecutionResult(status: .failed, error: .timeout, retrySafe: true, userMessage: "Compose failed.")], for: .compose)
        _ = await h.say("text Lee I'm running late")
        #expect(await h.requests.filter { Capability($0.action) == .compose }.count == 1)
        #expect(await h.state.stopReason == "Compose failed.")
    }

    @Test func unverifiedObservationStops() async throws {
        let h = Harness()
        // Claims success but the draft does not contain what the user dictated.
        let wrong = DraftSnapshot(channel: .messages, id: "x", recipients: ["Lee"], body: "Running behind", version: 1)
        await h.mock.inject([ExecutionResult(status: .completed, observation: .draft(wrong))], for: .compose)
        let r = await h.say("text Lee I'm running late, and show it to me")
        #expect(r.state.stopReason?.contains("couldn't confirm") == true)
        #expect(await h.context.draft == nil)  // unverified state is never recorded
    }

    @Test func partialAndUnsupportedStop() async throws {
        let h = Harness()
        await h.mock.inject([ExecutionResult(status: .unsupported, userMessage: "That window can't be moved.")], for: .arrangeWindows)
        let r = await h.say("move this window to the left half, then scroll down")
        #expect(r.state.stopReason == "That window can't be moved.")
        #expect(await h.requests.count == 1)
    }
}

@Suite("Send safety: confirmation binding and at-most-once")
struct SendSafetyTests {
    /// Reaches "awaiting confirmation" for a reviewed reply to Sarah Chen.
    func readyToConfirm() async -> Harness {
        let h = Harness()
        _ = await h.say(Fixture.acceptance)
        _ = await h.say("the first one")
        _ = await h.say("send it")
        return h
    }

    @Test func noMeansNotSent() async throws {
        let h = await readyToConfirm()
        _ = await h.say("no")
        #expect(await h.mock.sendRequests.isEmpty)
    }

    @Test func editWhileConfirmingInvalidatesApprovalAndRequiresNewReview() async throws {
        let h = await readyToConfirm()
        let edit = await h.say("change 3 to 3:30")
        #expect(edit.say.joined().contains("won't send"))
        #expect(await h.context.draft?.body == "I can meet at 3:30")
        #expect(await h.context.draftReviewed == false)
        #expect(await h.mock.sendRequests.isEmpty)

        let again = await h.say("send it")
        #expect(again.plan?.steps.map(\.capability) == [.review, .send])  // review of the new version first
        let request = try #require(await h.state.approvalRequest)
        #expect(request.draft.body == "I can meet at 3:30")
        _ = await h.say("yes")
        #expect(await h.mock.world.sent.count == 1)
        #expect(await h.mock.sendRequests.count == 1)
    }

    @Test func externalEditAfterAskingBlocksTheSend() async throws {
        let h = await readyToConfirm()
        let draftID = try #require(await h.context.draft?.id)
        await h.mock.userEditsDraft(draftID, body: "Actually, I can't make it")
        _ = await h.say("yes")
        #expect(await h.mock.world.sent.isEmpty)
        #expect(await h.state.stopReason?.contains("nothing was sent") == true)
        #expect(await h.context.draftReviewed == false)
        // The ledger does not block a later, properly reviewed send of the same draft.
        #expect(await h.session.runner.ledger.refusal(for: draftID) == nil)
    }

    @Test func unverifiedSendIsNeverRetried() async throws {
        let h = await readyToConfirm()
        await h.mock.setSendBehavior(.unverified)
        let r = await h.say("yes")
        #expect(r.state.stopReason?.contains("couldn't confirm it was sent") == true)
        let again = await h.say("send it")
        #expect(again.state.stopReason?.contains("couldn't confirm the last send") == true)
        #expect(await h.mock.sendRequests.count == 1)
    }

    @Test func sendTimeoutIsTreatedAsUnknown() async throws {
        let h = await readyToConfirm()
        await h.mock.setSendBehavior(.timeout)
        _ = await h.say("yes")
        _ = await h.say("send it")
        #expect(await h.mock.sendRequests.count == 1)
    }

    @Test func approvalIsSingleUseAndBound() async throws {
        let h = await readyToConfirm()
        _ = await h.say("yes")
        #expect(await h.session.runner.currentApproval == nil)
        let draft = DraftSnapshot(id: "d", recipients: ["a@b.c"], body: "x", version: 1)
        let approval = Approval(action: .send, draft: draft, issuedAt: Date())
        #expect(!approval.authorizes(.delete, on: draft, now: Date()))
        #expect(!approval.authorizes(.send, on: draft, now: Date().addingTimeInterval(Approval.lifetime + 1)))
        let edited = DraftSnapshot(id: "d", recipients: ["a@b.c"], body: "y", version: 2)
        #expect(!approval.authorizes(.send, on: edited, now: Date()))
        let readdressed = DraftSnapshot(id: "d", recipients: ["z@b.c"], body: "x", version: 1)
        #expect(!approval.authorizes(.send, on: readdressed, now: Date()))
    }

    @Test func otherCommandWhileConfirmingDropsTheSend() async throws {
        let h = await readyToConfirm()
        _ = await h.say("scroll down")
        _ = await h.say("yes")
        #expect(await h.mock.sendRequests.isEmpty)
    }

    @Test func ledgerRefusesSecondSendOfSameDraft() {
        var ledger = SendLedger()
        ledger.record("d1", .sent)
        #expect(ledger.refusal(for: "d1") != nil)
        ledger.record("d2", .inFlight)
        #expect(ledger.refusal(for: "d2") != nil)
        ledger.clearInFlight("d2")
        #expect(ledger.refusal(for: "d2") == nil)
    }
}

/// Regression (live voice test, 2026-11-14): Argmax finalized "Um, open notes"; the clause
/// splitter produced a filler-only clause "Um" that failed the whole utterance.
@Suite("Filler clauses")
struct FillerClauseTests {
    @Test(arguments: ["Um, open notes", "Uh, open notes.", "um open notes", "Erm, uh, open notes"])
    func fillerBeforeCommandStillPlans(utterance: String) async {
        let planner = TaskPlanner(router: IntentRouter(model: FillerTestModel()).core)
        guard case .plan(let plan) = await planner.plan(utterance, context: .empty) else {
            Issue.record("no plan for \(utterance)")
            return
        }
        #expect(plan.steps.map(\.action) == [.activateApp(.notes)])
    }

    @Test func fillerOnlyIsStillEmpty() async {
        let planner = TaskPlanner(router: IntentRouter(model: FillerTestModel()).core)
        guard case .failure(.emptyInput) = await planner.plan("Um, uh.", context: .empty) else {
            Issue.record("expected emptyInput")
            return
        }
    }

    @Test func fillerWordsInsideContentAreKept() {
        #expect(!TaskPlanner.isFillerOnly("um the album"))
        #expect(TaskPlanner.isFillerOnly("Um,"))
    }
}

private struct FillerTestModel: TracedIntentClassifying {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "model disabled", source: .model(id: "none"))),
                            attempts: [])
    }
}

/// Regression (live voice test, 2026-11-14): "I meant Sarah Chen" when two of three candidates
/// were hers re-asked the full list instead of narrowing it.
@Suite("Narrowing a choice")
struct NarrowingTests {
    static let candidates = [
        MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", subject: "Meeting tomorrow", epoch: 1),
        MessageRef(channel: .mail, id: "m2", sender: "Sarah Okafor", subject: "Lunch on Friday?", epoch: 1),
        MessageRef(channel: .mail, id: "m4", sender: "Sarah Chen", subject: "Launch checklist", epoch: 1),
    ]

    @Test func partialAnswerNarrowsToMatchingSubset() {
        #expect(PlanRunner.narrow("I meant Sarah Chen", from: Self.candidates)?.map(\.id) == ["m1", "m4"])
    }

    @Test func noNarrowingWhenNothingOrEverythingMatches() {
        #expect(PlanRunner.narrow("the blue one", from: Self.candidates) == nil)
        #expect(PlanRunner.narrow("Sarah", from: Self.candidates) == nil, "all three match: not narrower")
    }

    @Test func narrowedQuestionThenOrdinalPicksWithinSubset() async {
        let world = MockExecutor.World(activeApp: .mail, messages: Self.candidates)
        let session = TaskSession(store: IntentRouter(model: FillerTestModel()), executor: MockExecutor(world: world))
        guard case .awaitingChoice = await session.handle("find Sarah's email").state else { Issue.record("no question"); return }
        let narrowed = await session.handle("I meant Sarah Chen")
        guard case .awaitingChoice(let q) = narrowed.state else { Issue.record("not narrowed: \(narrowed.say)"); return }
        #expect(q.candidates.map(\.id) == ["m1", "m4"])
        #expect(narrowed.say.first?.hasPrefix("2 of those match") == true)
        let done = await session.handle("the second one")
        guard case .completed = done.state else { Issue.record("state \(done.state)"); return }
        #expect(await session.store.context.selectedMessage?.id == "m4", "second of the narrowed list")
    }
}

/// T-023A planning: trailing review requests and dictated reply content.
@Suite("Reply planning")
struct ReplyPlanningTests {
    static func context() -> ConversationContext {
        var c = ConversationContext.empty
        c.selectedMessage = MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", senderAddress: "sarah.chen@example.invalid",
                                       subject: "Meeting tomorrow", epoch: 1)
        c.openMessage = "Meeting tomorrow"
        c.notePerson("Sarah Chen")
        c.activeApp = .mail
        return c
    }

    @Test func trailingReviewIsSplitOffTheContent() async {
        let planner = TaskPlanner(router: IntentRouter(model: FillerTestModel()).core)
        guard case .plan(let p) = await planner.plan("Reply saying I can meet at 3 and show it to me", context: Self.context()) else {
            Issue.record("no plan"); return
        }
        #expect(p.steps.map(\.action) == [.createDraft(recipient: "Sarah Chen", content: "I can meet at 3"), .requestReview])
        #expect(p.steps[0].repliesToSelectedMessage)
    }

    @Test func splitTrailingReviewOnlyAtTheEnd() {
        #expect(TaskPlanner.splitTrailingReview("Reply saying I'll show it to you tomorrow").1 == false)
        #expect(TaskPlanner.splitTrailingReview("reply saying ok, and then show me the draft").0 == "reply saying ok")
    }

    @Test func dictatedAnswerIsOneReplyClause() async {
        var c = Self.context()
        c.pending = .draftContent(recipient: "Sarah Chen")
        let planner = TaskPlanner(router: IntentRouter(model: FillerTestModel()).core)
        guard case .plan(let p) = await planner.plan("Sounds good, let me know if 3 works", context: c) else {
            Issue.record("no plan"); return
        }
        #expect(p.steps.map(\.action) == [.createDraft(recipient: "Sarah Chen", content: "Sounds good, let me know if 3 works")])
        #expect(p.steps[0].repliesToSelectedMessage, "threaded although the answer has no reply word")
    }
}
