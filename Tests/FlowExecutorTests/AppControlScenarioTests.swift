import CoreGraphics
import FlowCore
@testable import FlowExecutor
@testable import FlowHUD
import FlowLLM
import FlowMailSend
import FlowPlanner
import FlowRouting
@testable import FlowSession
import Foundation
import Testing

/// ADR 0011 acceptance scenarios over the real router, planner, executor and HUD state, with
/// simulated windows and Mail. The HUD state is fed from the coordinator's real event stream.
@MainActor
@Suite("Usability scenarios: app control, persistent questions, HUD, safety", .serialized)
struct AppControlScenarioTests {
    @MainActor
    final class Flow {
        let rig: Rig
        let store: IntentRouter
        let coordinator: VoiceSessionCoordinator
        var hud = HUDState()
        private var listener: Task<Void, Never>?

        init(sending: MailSendMode? = nil) {
            rig = Rig(drafting: true, sending: sending)
            for app in [KnownApp.calendar, .notes, .mail] {
                rig.windows.openCreatesWindowFor[app.bundleIdentifier] = CGRect(x: 100, y: 100, width: 800, height: 600)
            }
            store = IntentRouter(model: ConfirmedSendTests.Model())
            coordinator = VoiceSessionCoordinator(session: TaskSession(store: store, executor: rig.executor), transcriber: nil,
                                                  permission: nil)
            listener = Task { [weak self, coordinator] in
                for await e in coordinator.events { self?.hud.apply(.coordinator(e)) }
            }
        }

        /// Typed exactly like a finalized utterance; waits until the HUD has seen the result.
        @discardableResult
        func say(_ text: String) async -> SessionTurn? {
            let t = await coordinator.submit(text)
            _ = await soon(.seconds(1)) { self.hud.recent.first?.heard == HUDState.truncate(text, HUDState.maxRecentLength) }
            try? await Task.sleep(for: .milliseconds(20))
            return t
        }

        var front: String? { rig.windows.frontmostApp()?.name }
        var said: String { hud.outcome?.text ?? "" }
    }

    // MARK: Scenario A — app control

    @Test func scenarioA_openSwitchGoBackMinimizeRestore() async throws {
        let f = Flow()
        await f.say("Open Notes")
        #expect(f.front == "Notes")
        await f.say("Switch to Calendar")
        #expect(f.front == "Calendar")
        await f.say("Go back to Notes")
        #expect(f.front == "Notes")
        await f.say("Minimize this window")
        let notesWindow = try #require(f.rig.windows.windows.values.first { $0.app.name == "Notes" })
        #expect(notesWindow.isMinimized)
        #expect(f.hud.outcome?.kind == .verified)
        await f.say("Restore it.")
        #expect(f.rig.windows.windows[notesWindow.id]?.isMinimized == false)
        #expect(f.hud.outcome?.kind == .verified, "\(f.said)")
        #expect(f.rig.executor.log.map(\.action) == ["activate_app", "activate_app", "activate_app", "minimize_window", "restore_window"])
    }

    @Test func bareGoBackReturnsToThePreviousApp() async {
        let f = Flow()
        await f.say("Open Notes")
        await f.say("Switch to Mail")
        await f.say("Go back")
        #expect(f.front == "Notes")
    }

    @Test func showMyOpenWindowsListsThemWithoutChangingAnything() async {
        let f = Flow()
        await f.say("Open Notes")
        await f.say("Open Calendar")
        let before = f.rig.windows.mutations
        await f.say("Show me my open windows.")
        #expect(f.said.contains("Notes") && f.said.contains("Calendar"), "\(f.said)")
        #expect(f.rig.windows.mutations == before)
    }

    @Test func closeNotesClosesTheWindowNotTheApp() async {
        let f = Flow()
        await f.say("Open Notes")
        await f.say("Close Notes.")
        #expect(f.rig.windows.windows.values.allSatisfy { $0.app.name != "Notes" })
        #expect(f.rig.windows.running[KnownApp.notes.bundleIdentifier] != nil)
        #expect(f.hud.outcome == HUDOutcome(kind: .verified, text: "Done: Close Notes."), "\(f.said)")
        #expect(f.rig.executor.log.last?.userMessage.contains("Notes is still open") == true)
    }

    @Test func closeWithUnsavedChangesLeavesTheSheetForTheUser() async throws {
        let f = Flow()
        await f.say("Open Notes")
        let id = try #require(f.rig.windows.windows.values.first { $0.app.name == "Notes" }?.id)
        f.rig.windows.unsaved = [id]
        await f.say("Close this window.")
        #expect(f.rig.windows.windows[id] != nil)
        #expect(f.hud.outcome?.kind == .notDone)
        #expect(f.said.contains("asking whether to save"))
    }

    @Test func quitIsRefusedAndExplained() async {
        let f = Flow()
        await f.say("Open Notes")
        await f.say("Quit Notes")
        #expect(f.rig.windows.running[KnownApp.notes.bundleIdentifier] != nil)
        #expect(f.said.contains("can't quit"))
    }

    @Test func missingAndAmbiguousWindowsAreExplained() async {
        let f = Flow()
        await f.say("Minimize the Safari window")
        #expect(f.hud.outcome?.kind == .notDone)
        #expect(f.said.contains("Safari isn't open"), "\(f.said)")
        f.rig.windows.addWindow(.notes, "Groceries", CGRect(x: 0, y: 0, width: 300, height: 300))
        f.rig.windows.addWindow(.notes, "Ideas", CGRect(x: 0, y: 0, width: 300, height: 300))
        await f.say("Close Notes")
        #expect(f.rig.windows.windows.values.filter { $0.app.name == "Notes" }.count == 2, "nothing closed when ambiguous")
        #expect(f.said.contains("2 windows") || f.said.contains("Which"), "\(f.said)")
    }

    // MARK: Scenario B — persistent clarification across app switches

    @Test func scenarioB_choicesStayOpenWhileMailIsFrontmostAndAnotherAppIsOpened() async throws {
        let f = Flow()
        await f.say("Find Sarah's email")
        #expect(f.hud.activity == .awaitingChoice)
        #expect(f.hud.choices.count >= 2)
        #expect(f.hud.choices.first?.text.contains("Sarah Chen") == true)
        // Mail comes to the front (as it does when Flow searches it); the HUD state doesn't depend on Flow's window.
        _ = f.rig.windows.activate(f.rig.windows.launch(.mail))
        // A quick app command does not drop the question.
        await f.say("Switch to Calendar")
        #expect(f.front == "Calendar")
        #expect(f.hud.activity == .awaitingChoice, "still waiting for the choice")
        #expect(f.hud.choices.count >= 2)
        let still = try #require(await f.coordinator.turns.last)
        #expect(still.say.contains { $0.hasPrefix("Still waiting.") })
        await f.say("The first one")
        #expect(await f.store.context.selectedMessage?.subject == "[FlowTest] Meeting tomorrow")
        #expect(f.hud.expectsResponse == false)
        #expect(f.hud.outcome?.kind == .verified)
    }

    @Test func routerQuestionSurvivesAQuickAppCommand() async throws {
        let f = Flow()
        await f.say("Find Sarah's email")
        await f.say("The first one")
        await f.say("Reply to it")
        #expect(f.hud.activity == .awaitingAnswer)
        await f.say("Switch to Mail")
        #expect(f.front == "Mail")
        #expect(f.rig.draftBackend.creates == 0, "“switch to Mail” is not the reply text")
        let turn = try #require(await f.coordinator.turns.last)
        #expect(turn.say.contains { $0.contains("Still waiting. What should the reply") }, "\(turn.say)")
        await f.say("I can meet at 3")
        #expect(f.rig.draftBackend.open.first?.body == "I can meet at 3")
    }

    // MARK: Scenario C — state is readable without the Voice tab (HUD state carries everything)

    @Test func scenarioC_everythingNeededToAnswerIsInTheHUD() async {
        let f = Flow()
        await f.say("Find Sarah's email")
        #expect(f.hud.question != nil)
        #expect(!f.hud.choices.isEmpty)
        #expect(f.hud.hint.contains("number"))
        #expect(f.hud.lastHeard == "Find Sarah's email")
        await f.say("2")
        #expect(await f.store.context.selectedMessage != nil)
    }

    // MARK: Scenario D — safety

    @Test func scenarioD_sendAndDeleteCannotBypassApproval() async throws {
        let f = Flow(sending: .live)
        await f.say("Find Sarah's email")
        await f.say("The first one")
        await f.say("Reply saying I can meet at 3:30.")
        await f.say("Send that reply.")
        #expect(f.hud.activity == .awaitingConfirmation)
        #expect(f.hud.question?.contains("I can meet at 3:30") == true)
        // The HUD has no approval path; switching apps abandons the confirmation (ADR 0010/0011).
        await f.say("Switch to Calendar")
        #expect(f.hud.activity != .awaitingConfirmation)
        await f.say("yes")
        #expect(f.rig.sendTransport.sendCalls == 0)
        // Delete requests are declined.
        await f.say("Delete that email")
        #expect(f.rig.draftBackend.open.count == 1)
        #expect(f.rig.sendTransport.sendCalls == 0)
    }

    @Test func stopRemainsResponsiveAndClearsTheQuestion() async {
        let f = Flow()
        await f.say("Find Sarah's email")
        #expect(f.hud.expectsResponse)
        await f.say("stop")
        #expect(!f.hud.expectsResponse)
        #expect(f.hud.outcome?.kind == .cancelled)
    }
}
