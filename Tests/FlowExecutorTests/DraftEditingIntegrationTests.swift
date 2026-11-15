import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowMail
import FlowPlanner
import FlowRouting
import Foundation
import Testing

/// Mail draft editing (T-023B) through the real router, planner and executor, over
/// **simulated** Mail (fake scripting backend + fake Accessibility inspector). Nothing here
/// touches macOS; the real-Mail path is covered by the gated live test only.
@MainActor
@Suite("Draft editing: TaskSession + MacPlanExecutor (simulated Mail)", .serialized)
struct DraftEditingIntegrationTests {
    @MainActor
    struct Flow {
        let rig: Rig
        let store = IntentRouter(model: ReplyDraftIntegrationTests.NoModel())
        let session: TaskSession

        init(editing: Bool = true) {
            rig = Rig(drafting: true, editing: editing)
            session = TaskSession(store: store, executor: rig.executor)
        }

        func say(_ s: String) async -> SessionReply { await session.handle(s) }
        var body: String? { rig.draftBackend.open.first?.body }

        /// "Find Sarah's email." / "The first one." / "Reply saying …"
        func reply(_ content: String = "I can meet at 3:30.") async -> Bool {
            guard case .awaitingChoice = await say("Find Sarah's email.").state else { return false }
            guard case .completed = await say("The first one.").state else { return false }
            guard case .completed = await say("Reply saying \(content)").state else { return false }
            return await store.context.draft != nil
        }
    }

    // MARK: Acceptance sequence

    @Test func acceptanceSequence() async throws {
        let f = Flow()
        #expect(await f.reply())
        #expect(f.body == "I can meet at 3:30")
        let created = try #require(await f.store.context.draft)

        let change = await f.say("Actually, change 3:30 to 4.")
        guard case .completed = change.state else { Issue.record("change: \(change.state) \(change.say)"); return }
        #expect(f.body == "I can meet at 4")
        #expect(change.say.contains { $0.contains("The draft now says") && $0.contains("I can meet at 4") })

        let append = await f.say("Also say I'll send the details tonight.")
        guard case .completed = append.state else { Issue.record("append: \(append.state) \(append.say)"); return }
        let appended = try #require(f.body)
        #expect(appended.hasPrefix("I can meet at 4"))
        #expect(appended.hasSuffix("I'll send the details tonight."))

        let review = await f.say("What does the draft say?")
        guard case .completed = review.state else { Issue.record("review: \(review.state) \(review.say)"); return }
        #expect(review.say.contains { $0.hasPrefix("Here's the draft") && $0.contains("I'll send the details tonight") })

        let undo = await f.say("Undo that last change.")
        guard case .completed = undo.state else { Issue.record("undo: \(undo.state) \(undo.say)"); return }
        #expect(f.body == "I can meet at 4")

        // Same draft throughout: one compose window, same recipients, subject and thread.
        #expect(f.rig.draftBackend.creates == 1)
        #expect(f.rig.draftBackend.open.count == 1)
        let now = try #require(await f.store.context.draft)
        #expect(now.id == created.id)
        #expect(now.recipients == ["sarah.chen@example.invalid"])
        #expect(now.subject == "Re: [FlowTest] Meeting tomorrow")
        #expect(now.inReplyTo == created.inReplyTo)
        #expect(now.version > created.version, "every edit is a new version (old approvals no longer match)")
        #expect(f.rig.draftBackend.open[0].cc.isEmpty && f.rig.draftBackend.open[0].bcc.isEmpty)
        #expect(!f.rig.executor.log.contains { $0.action == "request_send" })
    }

    @Test func theOtherBriefCommands() async throws {
        let f = Flow()
        #expect(await f.reply("I can meet tomorrow at 3:30. Thanks."))
        for (command, check) in [
            ("Add that I'll be ten minutes late.", { (b: String) in b.hasSuffix("I'll be ten minutes late.") }),
            ("Also say I'm available Friday.", { (b: String) in b.hasSuffix("I'm available Friday.") }),
            ("Replace tomorrow with Wednesday.", { (b: String) in b.contains("Wednesday") && !b.contains("tomorrow") }),
            ("Remove the last sentence.", { (b: String) in !b.contains("Friday") }),
            ("Undo that change.", { (b: String) in b.hasSuffix("I'm available Friday.") }),
        ] {
            let r = await f.say(command)
            guard case .completed = r.state else { Issue.record("\(command): \(r.state) \(r.say)"); return }
            #expect(check(f.body ?? ""), "\(command) → \(f.body ?? "nil")")
        }
        #expect(f.rig.draftBackend.creates == 1 && f.rig.draftBackend.open.count == 1)
    }

    // MARK: Questions go through the shared context

    @Test func duplicateWordAsksAndTheAnswerReachesFlowText() async throws {
        let f = Flow()
        #expect(await f.reply("Meet at 3 or call at 3"))
        let ask = await f.say("Change 3 to 4")
        guard case .stopped(_, let prompt) = ask.state else { Issue.record("ask: \(ask.state) \(ask.say)"); return }
        #expect(prompt.lowercased().contains("which"))
        guard case .textEdit = await f.store.context.pending else { Issue.record("no textEdit question pending"); return }
        #expect(f.body == "Meet at 3 or call at 3", "nothing changed while asking")
        let answer = await f.say("the second one")
        guard case .completed = answer.state else { Issue.record("answer: \(answer.state) \(answer.say)"); return }
        #expect(f.body == "Meet at 3 or call at 4")
        #expect(await f.store.context.pending == nil)
    }

    @Test func stopDropsTheDraftQuestion() async throws {
        let f = Flow()
        #expect(await f.reply("Meet at 3 or call at 3"))
        _ = await f.say("Change 3 to 4")
        _ = await f.say("stop")
        #expect(await f.store.context.pending == nil)
        _ = await f.say("the second one")
        #expect(f.body == "Meet at 3 or call at 3", "an answer after stop never edits")
    }

    // MARK: External changes, staleness, ambiguity

    @Test func editAfterAnExternalChangeUsesTheLiveTextAndKeepsTheUsersWords() async throws {
        let f = Flow()
        #expect(await f.reply())
        f.rig.draftBackend.open[0].body = "I can meet at 3:30, see you there"  // typed by the user
        let r = await f.say("Change 3:30 to 4")
        guard case .completed = r.state else { Issue.record("\(r.state) \(r.say)"); return }
        #expect(f.body == "I can meet at 4, see you there")
    }

    @Test func undoRefusesWhenTheUserRetypedTheEditedSpan() async throws {
        let f = Flow()
        #expect(await f.reply())
        _ = await f.say("Change 3:30 to 4")
        f.rig.draftBackend.open[0].body = "I can meet at 4:15"
        let r = await f.say("Undo that change")
        if case .completed = r.state { Issue.record("undo overwrote the user's edit") }
        #expect(f.body == "I can meet at 4:15")
    }

    @Test func duplicateDraftsWithTheSameSubjectAreAmbiguousNotGuessed() async throws {
        let f = Flow()
        #expect(await f.reply())
        // A second reply to the same message, same recipient, same text: indistinguishable.
        f.rig.draftBackend.open.append(.init(subject: "Re: [FlowTest] Meeting tomorrow", to: ["sarah.chen@example.invalid"],
                                             body: "I can meet at 3:30"))
        f.rig.compose.tokens = false  // no window identity to tell them apart
        let r = await f.say("Change 3:30 to 4")
        if case .completed = r.state { Issue.record("edited one of two identical drafts") }
        #expect(f.rig.draftBackend.open.allSatisfy { $0.body == "I can meet at 3:30" })
        #expect(!f.rig.draftBackend.log.contains("setContent"))
    }

    @Test func windowIdentityTellsSameTitledDraftsApart() async throws {
        let f = Flow()
        #expect(await f.reply())
        f.rig.draftBackend.open.append(.init(subject: "Re: [FlowTest] Meeting tomorrow", to: ["sarah.chen@example.invalid"],
                                             body: "Different text in another window"))
        let r = await f.say("Change 3:30 to 4")
        guard case .completed = r.state else { Issue.record("\(r.state) \(r.say)"); return }
        #expect(f.rig.draftBackend.open[0].body == "I can meet at 4")
        #expect(f.rig.draftBackend.open[1].body == "Different text in another window", "the other window is untouched")
    }

    @Test func aWriteTheWindowDoesNotShowIsNeverReportedAsDone() async throws {
        let f = Flow()
        #expect(await f.reply())
        f.rig.draftBackend.windowIgnoresWrites = true
        let r = await f.say("Change 3:30 to 4")
        if case .completed = r.state { Issue.record("reported success without on-screen proof") }
        #expect(r.say.joined().contains("couldn't confirm") || {
            if case .stopped(_, let why) = r.state { return why.contains("couldn't confirm") || why.contains("check") }
            return false
        }())
    }

    @Test func noDraftAsksInsteadOfEditing() async {
        let f = Flow()
        let r = await f.say("Remove the last sentence.")
        #expect(r.say.contains { $0.contains("no draft open") } || {
            if case .stopped(_, let why) = r.state { return why.contains("no draft") }
            return false
        }())
        #expect(f.rig.draftBackend.log.isEmpty)
    }

    @Test func editingIsOffByDefault() async throws {
        let f = Flow(editing: false)
        #expect(await f.reply())
        let r = await f.say("Change 3:30 to 4")
        if case .completed = r.state { Issue.record("edited with editing disabled") }
        #expect(f.body == "I can meet at 3:30")
        #expect(f.rig.executor.log.contains { $0.action == "edit_text" && $0.status == .unsupported })
    }

    @Test func quotedOriginalIsPreservedByteForByte() async throws {
        let f = Flow()
        #expect(await f.reply())
        let quote = "\n\nOn Fri 13 Nov, Sarah Chen <sarah.chen@example.invalid> wrote:\n> Can we meet tomorrow?\n>  Thanks"
        f.rig.draftBackend.open[0].body = "I can meet at 3:30" + quote
        let r = await f.say("Change 3:30 to 4")
        guard case .completed = r.state else { Issue.record("\(r.state) \(r.say)"); return }
        #expect(f.body == "I can meet at 4" + quote)
        let remove = await f.say("Remove the last sentence")
        // The only authored sentence: FlowText refuses to empty the draft, or removes it; the quote stays.
        _ = remove
        #expect(f.body?.hasSuffix(quote) == true)
    }
}
