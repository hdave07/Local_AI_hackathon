import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowMail
import FlowPlanner
import FlowRouting
import Foundation
import Testing

/// Reply drafting through the real TaskSession (router + planner) and real executor over
/// simulated Mail (T-023A).
@MainActor
@Suite("Reply drafts: TaskSession + MacPlanExecutor")
struct ReplyDraftIntegrationTests {
    struct NoModel: TracedIntentClassifying {
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))),
                                attempts: [])
        }
    }

    @MainActor
    struct Flow {
        let rig: Rig
        let store = IntentRouter(model: NoModel())
        let session: TaskSession

        init() {
            rig = Rig(drafting: true)
            session = TaskSession(store: store, executor: rig.executor)
        }

        /// Find Sarah's email and choose Sarah Chen's "Meeting tomorrow".
        func openChen() async -> Bool {
            guard case .awaitingChoice = await session.handle("Find Sarah's email").state else { return false }
            guard case .completed = await session.handle("the first one").state else { return false }
            return await store.context.selectedMessage?.subject == "[FlowTest] Meeting tomorrow"
        }
    }

    @Test func acceptanceReplySayingCreatesAThreadedDraftToTheSender() async throws {
        let f = Flow()
        #expect(await f.openChen())
        let reply = await f.session.handle("Reply saying I can meet at 3")
        guard case .completed = reply.state else { Issue.record("state \(reply.state) say \(reply.say)"); return }
        let draft = try #require(await f.store.context.draft)
        #expect(draft.recipients == ["sarah.chen@example.invalid"])
        #expect(draft.subject == "Re: [FlowTest] Meeting tomorrow")
        #expect(draft.body == "I can meet at 3")
        #expect(draft.inReplyTo == (await f.store.context.selectedMessage)?.id, "threaded to the chosen message")
        #expect(f.rig.draftBackend.creates == 1)
        #expect(f.rig.draftBackend.open.count == 1)
    }

    @Test func twoTurnReply() async throws {
        let f = Flow()
        #expect(await f.openChen())
        let ask = await f.session.handle("reply to it")
        #expect(ask.say == ["What should the reply to Sarah Chen say?"])
        #expect(f.rig.draftBackend.creates == 0, "nothing created before the content is known")
        let done = await f.session.handle("I can meet at 3, let me know if that works")
        guard case .completed = done.state else { Issue.record("state \(done.state) say \(done.say)"); return }
        #expect(await f.store.context.draft?.body == "I can meet at 3, let me know if that works", "dictated content kept whole")
        #expect(await f.store.context.draft?.recipients == ["sarah.chen@example.invalid"])
    }

    @Test func reviewPresentsTheLiveDraft() async throws {
        let f = Flow()
        #expect(await f.openChen())
        let r = await f.session.handle("Reply saying I can meet at 3 and show it to me")
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        #expect(await f.store.context.reviewedDraftVersion == 1)
        #expect(f.rig.draftBackend.log.contains("show"))
    }

    @Test func externalEditIsDetectedAndTheSnapshotReplaced() async throws {
        let f = Flow()
        #expect(await f.openChen())
        _ = await f.session.handle("Reply saying I can meet at 3")
        f.rig.draftBackend.open[0].body = "I can meet at 4 instead"  // the user typed in the compose window
        let r = await f.session.handle("show me the draft")
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        let draft = try #require(await f.store.context.draft)
        #expect(draft.version == 2)
        #expect(draft.body == "I can meet at 4 instead")
        #expect(await f.store.context.reviewedDraftVersion == 2, "what the user sees now is what was reviewed")
    }

    @Test func sendStaysDisabledEvenAfterYes() async {
        let f = Flow()
        #expect(await f.openChen())
        _ = await f.session.handle("Reply saying I can meet at 3 and show it to me")
        let ask = await f.session.handle("send it")
        guard case .awaitingConfirmation = ask.state else { Issue.record("state \(ask.state)"); return }
        let yes = await f.session.handle("yes")
        guard case .stopped(_, let reason) = yes.state else { Issue.record("state \(yes.state)"); return }
        #expect(reason.contains("disabled") || reason.contains("Nothing was sent"))
        #expect(f.rig.executor.log.contains { $0.action == "request_send" && $0.status == .unsupported })
        #expect(f.rig.draftBackend.open.count == 1, "the draft stays open and unsent")
    }

    @Test func recipientMismatchCreatesNothing() async {
        let f = Flow()
        #expect(await f.openChen())
        f.rig.draftBackend.replyTo = ["assistant@example.invalid"]  // e.g. a Reply-To header
        let r = await f.session.handle("Reply saying I can meet at 3")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.contains("not only sarah.chen@example.invalid"))
        #expect(await f.store.context.draft == nil)
        #expect(f.rig.draftBackend.open.isEmpty)
    }

    @Test func replyWhileStillChoosingNeverGuessesTheMessage() async {
        let f = Flow()
        guard case .awaitingChoice = await f.session.handle("Find Sarah's email").state else { Issue.record("no question"); return }
        let r = await f.session.handle("Reply saying I can meet at 3")
        #expect(f.rig.draftBackend.creates == 0, "no draft without a verified selected message")
        #expect(r.say.contains { $0.contains("Which message") || $0.contains("Find it first") || $0.contains("which one") })
    }

    @Test func stopDuringCreationRunsNoFurtherSteps() async {
        let f = Flow()
        #expect(await f.openChen())
        f.rig.draftBackend.createDelay = .milliseconds(400)
        let session = f.session
        let running = Task { await session.handle("Reply saying I can meet at 3 and show it to me") }
        try? await Task.sleep(for: .milliseconds(100))
        _ = await f.session.handle("stop")
        _ = await running.value
        #expect(f.rig.draftBackend.creates <= 1)
        #expect(!f.rig.draftBackend.log.contains("show"), "review never ran after stop")
    }
}

/// The user's live session (2026-11-14), replayed end to end over simulated Mail.
@MainActor
@Suite("Live session replay: reply flow")
struct LiveSessionReplayTests {
    @Test func replyToSarahsEmailThenDeleteThenReference() async throws {
        let f = ReplyDraftIntegrationTests.Flow()
        #expect(await f.openChen())
        let r = await f.session.handle("Can you reply to Sarah's email that I can meet at 3:30?")
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        #expect(await f.store.context.draft?.body == "I can meet at 3:30")

        let del = await f.session.handle("Actually, never mind. Can you delete that reply?")
        #expect(del.say.first?.contains("hasn't been sent") == true)
        #expect(f.rig.draftBackend.open.count == 1, "nothing deleted")

        let show = await f.session.handle("That reply that we just drafted")
        guard case .completed = show.state else { Issue.record("state \(show.state) say \(show.say)"); return }
        #expect(f.rig.draftBackend.log.contains("show"))
    }

    @Test func replyToSarahsEmailWithoutOpeningItFirstFindsItThenAsks() async throws {
        let f = ReplyDraftIntegrationTests.Flow()
        let r = await f.session.handle("Reply to Sarah's email saying I can meet at 3:30")
        guard case .awaitingChoice = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        #expect(f.rig.draftBackend.creates == 0, "never guesses which Sarah")
        let done = await f.session.handle("the first one")
        guard case .completed = done.state else { Issue.record("state \(done.state) say \(done.say)"); return }
        #expect(await f.store.context.draft?.body == "I can meet at 3:30")
        #expect(await f.store.context.draft?.recipients == ["sarah.chen@example.invalid"])
    }

    @Test func neverMindDropsTheReplyQuestion() async {
        let f = ReplyDraftIntegrationTests.Flow()
        #expect(await f.openChen())
        _ = await f.session.handle("reply to it")
        let nm = await f.session.handle("never mind")
        #expect(nm.say == ["Okay, never mind."])
        _ = await f.session.handle("open notes")
        #expect(f.rig.draftBackend.creates == 0, "“open notes” was a command, not reply content")
    }
}
