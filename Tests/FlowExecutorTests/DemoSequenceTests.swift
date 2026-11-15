import CoreGraphics
import FlowCore
@testable import FlowExecutor
import FlowMailSend
import FlowPlanner
import FlowRouting
@testable import FlowText
import Testing

/// The 90-second demo, end to end over the real router, planner and executor with simulated
/// windows and Mail (live verification is recorded separately in docs/evidence/demo-readiness.md).
@MainActor
@Suite("Demo sequence (simulated)", .serialized)
struct DemoSequenceTests {
    @Test func fullDemoSequence() async throws {
        let rig = Rig(drafting: true, editing: true, sending: .dryRun)
        for app in [KnownApp.calendar, .mail] { rig.windows.openCreatesWindowFor[app.bundleIdentifier] = CGRect(x: 100, y: 100, width: 800, height: 600) }
        rig.mail.add("Sarah Okafor", "sarah.okafor@example.invalid", "[FlowTest] Coffee tomorrow?", mailbox: "Import/FlowTest", account: nil, daysAgo: 0)
        let s = TaskSession(store: IntentRouter(model: ConfirmedSendTests.Model()), executor: rig.executor)

        // A — tile (deterministic; both apps opened and tiled)
        var r = await s.handle("Open Mail and Calendar and put them side by side.")
        guard case .completed = r.state else { Issue.record("A: \(r.state) \(r.say)"); return }
        #expect(rig.executor.log.last?.action == "tile_windows")

        // C — ambiguous search, then choose the second
        r = await s.handle("Find Sarah's email about tomorrow.")
        guard case .awaitingChoice(let q) = r.state else { Issue.record("C: \(r.state) \(r.say)"); return }
        #expect(q.candidates.count == 2)
        r = await s.handle("The second one.")
        guard case .completed = r.state else { Issue.record("C2: \(r.state)"); return }
        let opened = try #require(await s.store.context.selectedMessage)
        #expect(opened.subject == "[FlowTest] Meeting tomorrow")

        // D — reply (speech recognition writes digits)
        r = await s.handle("Reply saying I can meet at 4.")
        guard case .completed = r.state else { Issue.record("D: \(r.state) \(r.say)"); return }
        #expect(rig.draftBackend.open.first?.to == ["sarah.chen@example.invalid"])

        // E — correction spoken in words
        r = await s.handle("Actually, change four to four thirty.")
        guard case .completed = r.state else { Issue.record("E: \(r.state) \(r.say)"); return }
        #expect(rig.draftBackend.open.first?.body == "I can meet at 4:30")
        #expect(rig.draftBackend.open.first?.to == ["sarah.chen@example.invalid"])

        // F — readback of the live draft
        r = await s.handle("Read my reply.")
        #expect(r.say.joined().contains("I can meet at 4:30"), "\(r.say)")

        // G — confirmation, then a dry-run send
        r = await s.handle("Send that reply.")
        guard case .awaitingConfirmation(let req) = r.state else { Issue.record("G: \(r.state)"); return }
        #expect(req.prompt.contains("sarah.chen@example.invalid") && req.prompt.contains("I can meet at 4:30"))
        r = await s.handle("Yes, send it.")
        #expect(r.say.joined().contains("Dry run"))
        #expect(rig.sender?.dryRunLog.count == 1)
        #expect(rig.sendTransport.sendCalls == 0)
    }

    @Test(arguments: [
        ("I can meet at 4", "change four to four thirty", "I can meet at 4:30"),
        ("I can meet at four", "change four to four thirty", "I can meet at four thirty"),
        ("See you at 4:30", "change four thirty to five", "See you at 5"),
        ("Lunch at 12", "change twelve to half past one", "Lunch at 1:30"),
    ])
    func numbersMatchHoweverTheyAreWritten(text: String, command: String, expected: String) throws {
        guard case .edit(let op) = EditCommandParser.parse(command) else { Issue.record("not an edit: \(command)"); return }
        guard case .plan(let plan) = TextEditor.plan(op, on: TextSnapshot(document: TextDocumentID("demo"), text: text, version: 1, selection: nil)) else {
            Issue.record("no plan for \(command) on \(text)"); return
        }
        #expect(plan.after == expected, "\(plan.after)")
    }

    @Test(arguments: [
        "Open Mail and Calendar and put them side by side.",
        "put mail and calendar side by side",
        "can you show calendar and mail next to each other",
        "split screen mail with calendar",
    ])
    func sideBySideInAnyWording(utterance: String) {
        #expect(IntentRouterCore.isWholeUtteranceCommand(utterance), "\(utterance)")
    }
}
