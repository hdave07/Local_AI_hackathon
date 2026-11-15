import FlowCore
import FlowLLM
@testable import FlowRouting
import Foundation
import Testing

/// Deterministic routing of draft edit commands (T-023B, ADR 0010). No model is called.
@Suite("Draft edit routing")
struct DraftEditRoutingTests {
    static let draft = DraftSnapshot(channel: .mail, id: "d-1", recipients: ["sarah.chen@example.invalid"],
                                     subject: "Re: [FlowTest] Meeting tomorrow", body: "I can meet at 3:30 tomorrow.", version: 1, inReplyTo: "m1")
    static let withDraft = ConversationContext(hasDraft: true, draft: draft)

    @Test(arguments: [
        ("Add that I'll be ten minutes late.", "Add that I'll be ten minutes late."),
        ("Also say I'm available Friday.", "Also say I'm available Friday."),
        ("Change 3:30 to 4.", "Change 3:30 to 4."),
        ("Replace tomorrow with Wednesday.", "Replace tomorrow with Wednesday."),
        ("Remove the last sentence.", "Remove the last sentence."),
        ("Undo that change.", "Undo that change."),
        ("Actually, change 3:30 to 4.", "change 3:30 to 4."),
        ("Flow, undo that last change.", "undo that last change."),
    ])
    func briefCommandsBecomeEditText(utterance: String, payload: String) async throws {
        let model = FakeModel()
        let d = await route(utterance, Self.withDraft, model: model)
        let intent = try #require(try? d.outcome.get())
        #expect(intent.action == .editText(payload))
        #expect(intent.kind == .edit)
        #expect(intent.source == .deterministic)
        #expect(model.calls.isEmpty, "no model call for edit commands")
    }

    @Test func whatDoesTheDraftSayIsAReviewNotAnEdit() async throws {
        let d = await route("What does the draft say?", Self.withDraft)
        #expect(try d.outcome.get().action == .requestReview)
    }

    @Test(arguments: ["Remove the last sentence.", "Undo that change.", "Also say I'm available Friday."])
    func withoutADraftFlowAsks(utterance: String) async throws {
        let model = FakeModel()
        let d = await route(utterance, .empty, model: model)
        let intent = try d.outcome.get()
        #expect(intent.kind == .clarification)
        #expect(intent.summary.contains("no draft open"))
        #expect(model.calls.isEmpty)
    }

    @Test(arguments: ["Add Sarah to the meeting", "add an event tomorrow"])
    func addingSomethingElseIsNotDraftText(utterance: String) async throws {
        let d = await route(utterance, Self.withDraft)
        if case .success(let i) = d.outcome, case .editText = i.action { Issue.record("“\(utterance)” edited the draft") }
    }

    @Test func discardingTheDraftIsNeverAnEdit() async throws {
        let d = await route("delete the draft", Self.withDraft)
        if case .success(let i) = d.outcome, case .editText = i.action { Issue.record("deleting the draft became an edit") }
    }

    @Test func modelCannotEmitEditText() {
        #expect(!ActionType.modelEmittable.contains(.editText))
    }

    // MARK: FlowText's questions live in the shared context

    @Test(arguments: ["the second one", "2", "all of them", "the last one"])
    func occurrenceAnswersGoBackToFlowText(answer: String) async throws {
        var ctx = Self.withDraft
        ctx.pending = .textEdit(prompt: "Which “3”?", options: ["…meet at [3] or…", "…call at [3]"])
        let d = await route(answer, ctx)
        #expect(try d.outcome.get().action == .editText(answer))
        #expect(d.stage == .followUp)
    }

    @Test(arguments: ["keep it", "discard it", "yes", "no"])
    func previewAnswersGoBackToFlowText(answer: String) async throws {
        var ctx = Self.withDraft
        ctx.pending = .textEdit(prompt: "Here's the change: “…”. Keep it, or discard it?", options: [])
        let d = await route(answer, ctx)
        #expect(try d.outcome.get().action == .editText(answer))
    }

    @Test func anUnrelatedRequestIsNotTakenAsTheAnswer() async throws {
        var ctx = Self.withDraft
        ctx.pending = .textEdit(prompt: "Which “3”?", options: ["a", "b"])
        let d = await route("open notes", ctx)
        #expect(try d.outcome.get().action == .activateApp(.notes))
    }
}
