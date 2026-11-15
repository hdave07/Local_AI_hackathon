import FlowCore
@testable import FlowRouting
import Testing

/// ADR 0011: natural app and window commands route deterministically (the model is never asked).
@Suite("App and window commands by voice")
struct AppWindowRoutingTests {
    @Test(arguments: [
        ("Open Notes.", FlowAction.activateApp(.notes)),
        ("Switch to Mail.", .activateApp(.mail)),
        ("Bring Calendar to the front.", .activateApp(.calendar)),
        ("bring the calendar forward", .activateApp(.calendar)),
        ("Go back to Notes.", .activateApp(.notes)),
        ("switch back to mail", .activateApp(.mail)),
        ("take me to the notes app", .activateApp(.notes)),
        ("Close Notes.", .closeWindow(.app(.notes))),
        ("Close this window.", .closeWindow(.active)),
        ("close the mail window", .closeWindow(.app(.mail))),
        ("Minimize this window.", .minimizeWindow(.active)),
        ("minimize", .minimizeWindow(.active)),
        ("minimise safari", .minimizeWindow(.app(.safari))),
        ("Restore the notes window", .restoreWindow(.app(.notes))),
        ("Show me my open windows.", .listWindows),
        ("what windows are open", .listWindows),
        ("list windows", .listWindows),
        ("Um, open Notes", .activateApp(.notes)),
        ("No wait, switch to Calendar", .activateApp(.calendar)),
    ])
    func routes(utterance: String, expected: FlowAction) async throws {
        let model = FakeModel()
        let d = await route(utterance, model: model)
        #expect(try d.outcome.get().action == expected, "\(utterance)")
        #expect(model.calls.isEmpty, "\(utterance) reached the model")
    }

    @Test func restoreItUsesTheWindowFlowLastActedOn() async throws {
        var ctx = ConversationContext()
        ctx.selectedWindow = SelectedWindow(app: .notes, title: "Groceries", windowID: "w1")
        for u in ["Restore it.", "Restore that window", "restore", "bring it back"] {
            let d = await route(u, ctx)
            #expect(try d.outcome.get().action == .restoreWindow(.app(.notes)), "\(u)")
        }
    }

    @Test func bareGoBackUsesThePreviousApp() async throws {
        var ctx = ConversationContext()
        ctx.activeApp = .notes
        ctx.activeApp = .calendar
        #expect(ctx.previousApp == .notes)
        let d = await route("go back", ctx)
        #expect(try d.outcome.get().action == .activateApp(.notes))
    }

    @Test func bareGoBackWithoutHistoryAsks() async throws {
        let d = await route("go back", .empty)
        #expect(try d.outcome.get().kind == .clarification)
        #expect(d.pending == .app(then: .activate))
    }

    @Test(arguments: ["Quit Notes", "force quit Mail", "kill Safari", "shut down Notes"])
    func quittingIsNeverDone(utterance: String) async throws {
        let d = await route(utterance)
        let intent = try d.outcome.get()
        #expect(intent.action == nil)
        #expect(intent.summary.contains("can't quit"), "\(utterance): \(intent.summary)")
    }

    @Test func closingAnUnknownThingIsExplained() async throws {
        let intent = try await route("close the spaceship").outcome.get()
        #expect(intent.action == nil)
        #expect(intent.summary.contains("which window"))
    }

    @Test func closingTheDraftIsStillTheDraftRule() async throws {
        var ctx = ConversationContext()
        ctx.hasDraft = true
        let intent = try await route("close that reply", ctx).outcome.get()
        #expect(intent.action == nil)
        #expect(intent.summary.contains("draft") || intent.summary.contains("reply"))
    }

    @Test func modelCannotEmitWindowActions() {
        for type in [ActionType.minimizeWindow, .restoreWindow, .closeWindow, .listWindows] {
            #expect(!ActionType.modelEmittable.contains(type))
        }
    }
}
