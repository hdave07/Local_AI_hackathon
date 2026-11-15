import FlowCore
@testable import FlowPlanner
import FlowRouting
import Foundation
import Testing

/// `edit_text` through router → planner → MockExecutor (FlowText over simulated drafts).
@Suite("Planner: draft editing (mock executor)", .serialized)
struct DraftEditingPlanTests {
    func drafted(_ content: String = "I can meet at 3:30.") async throws -> Harness {
        let h = Harness()
        _ = await h.say("Find Sarah's email about tomorrow")
        _ = await h.say("Sarah Chen")
        let r = await h.say("Reply saying \(content)")
        guard case .completed = r.state else { throw Fail("reply: \(r.state) \(r.say)") }
        return h
    }
    struct Fail: Error { let why: String; init(_ w: String) { why = w } }

    func body(_ h: Harness) async -> String? {
        guard let id = await h.context.draft?.id else { return nil }
        return await h.mock.world.drafts[id]?.body
    }

    @Test func editIsOneVerifiedStepBoundToTheCurrentDraft() async throws {
        let h = try await drafted()
        let draft = try #require(await h.context.draft)
        let r = await h.say("Change 3:30 to 4")
        guard case .completed = r.state else { Issue.record("\(r.state) \(r.say)"); return }
        let edit = try #require(await h.requests.last)
        #expect(edit.action == .editText("Change 3:30 to 4"))
        #expect(edit.bindings.draft?.id == draft.id)
        #expect(edit.expectation == .draftEdited)
        #expect(await body(h) == "I can meet at 4")
        #expect(await h.context.draft?.version == draft.version + 1, "the context holds the verified new version")
    }

    @Test func editInvalidatesAnEarlierReviewSoSendNeedsANewOne() async throws {
        let h = try await drafted()
        _ = await h.say("show me the draft")
        let reviewed = await h.context.reviewedDraftVersion
        _ = await h.say("Change 3:30 to 4")
        #expect(await h.context.draft?.version != reviewed, "an approval for the old version can't match the edited draft")
        let send = await h.say("send it")
        if case .awaitingConfirmation(let req) = send.state { #expect(req.draft.body == "I can meet at 4") }
        #expect(await h.mock.world.sent.isEmpty)
    }

    @Test func undoWalksBack() async throws {
        let h = try await drafted()
        _ = await h.say("Change 3:30 to 4")
        _ = await h.say("Also say I'll bring the notes.")
        #expect(await body(h) == "I can meet at 4. I'll bring the notes.")
        _ = await h.say("Undo that change")
        #expect(await body(h) == "I can meet at 4")
        _ = await h.say("Undo that change")
        #expect(await body(h) == "I can meet at 3:30")
        let none = await h.say("Undo that change")
        #expect(none.state.stopReason?.contains("nothing") == true || none.state.stopReason?.contains("no change") == true)
    }

    @Test func occurrenceQuestionPausesInTheSharedContext() async throws {
        let h = try await drafted("Meet at 3 or call at 3")
        let ask = await h.say("Change 3 to 4")
        #expect(ask.state.stopReason?.lowercased().contains("which") == true)
        guard case .textEdit(_, let options) = await h.context.pending else { Issue.record("not pending"); return }
        #expect(options.count == 2)
        _ = await h.say("all of them")
        #expect(await body(h) == "Meet at 4 or call at 4")
    }

    @Test func externalEditBetweenTurnsIsNotOverwritten() async throws {
        let h = try await drafted()
        let id = try #require(await h.context.draft?.id)
        await h.mock.userEditsDraft(id, body: "I can meet at 3:30 or later")
        let r = await h.say("Change 3:30 to 4")
        guard case .completed = r.state else { Issue.record("\(r.state)"); return }
        #expect(await body(h) == "I can meet at 4 or later", "edited on the live text; the user's words kept")
    }

    @Test func stopBeforeTheEditLandsChangesNothing() async throws {
        let h = try await drafted()
        await h.mock.delay(.editText, by: .milliseconds(300))
        let session = h.session
        let running = Task { await session.handle("Change 3:30 to 4") }
        try await Task.sleep(for: .milliseconds(60))
        _ = await h.say("stop")
        _ = await running.value
        #expect(await body(h) == "I can meet at 3:30")
    }

    @Test func readBackSaysWhatIsOnScreen() async throws {
        let h = try await drafted()
        _ = await h.say("Change 3:30 to 4")
        let r = await h.say("What does the draft say?")
        #expect(r.say.contains { $0.contains("Here's the draft") && $0.contains("I can meet at 4") })
    }
}
