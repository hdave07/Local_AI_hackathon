import CoreGraphics
import FlowAX
import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowMail
import FlowPlanner
import FlowRouting
import FlowWindow
import Foundation
import Testing

@MainActor
struct Rig {
    let windows = FakeWindowBackend()
    let ui = mailLikeBackend()
    let mail = FakeMailBackend()
    let draftBackend: FakeDraftBackend
    let compose: FakeComposeInspector
    let executor: MacPlanExecutor

    init(scope: ExecutorConfiguration.MailScope = .testMailbox("FlowTest"), drafting: Bool = false) {
        for app in [KnownApp.notes, .mail] {
            windows.openCreatesWindowFor[app.bundleIdentifier] = CGRect(x: 100, y: 100, width: 800, height: 600)
        }
        // Synthetic test mailbox, plus a "real" inbox message that must never be touched in test mode.
        mail.add("Sarah Chen", "sarah.chen@example.invalid", "[FlowTest] Meeting tomorrow", mailbox: "Import/FlowTest", account: nil, daysAgo: 1)
        mail.add("Sarah Okafor", "sarah.okafor@example.invalid", "[FlowTest] Lunch on Friday?", mailbox: "Import/FlowTest", account: nil, daysAgo: 2)
        mail.add("Priya Patel", "priya.patel@example.invalid", "[FlowTest] Project budget review", mailbox: "Import/FlowTest", account: nil, daysAgo: 3)
        mail.add("Sarah Real", "sarah@real.example", "Private inbox message", mailbox: "INBOX", account: "Work")
        draftBackend = FakeDraftBackend(mail: mail)
        compose = FakeComposeInspector(backend: draftBackend)
        var dc = MailDraftController.Configuration()
        dc.verifyTimeout = .milliseconds(30)
        dc.pollInterval = .milliseconds(5)
        let drafts = drafting ? MailDraftController(mail: mail, backend: draftBackend, inspector: compose, configuration: dc) : nil
        executor = MacPlanExecutor(window: makeController(windows), navigator: makeNavigator(ui), mail: makeMail(mail),
                                   drafts: drafts, configuration: ExecutorConfiguration(mailScope: scope))
    }

    func run(_ action: FlowAction, channel: MessageChannel? = nil, bindings: StepBindings = StepBindings()) async -> ExecutionResult {
        await executor.execute(ExecutionRequest(planID: UUID(), stepID: 1, attempt: 1, action: action, channel: channel,
                                                bindings: bindings, expectation: .uiActed))
    }

    var realInboxTouched: Bool {
        mail.log.contains { $0.hasPrefix("open") || $0.hasPrefix("content") || $0.hasPrefix("lookup") }
            && mail.messages.keys.contains { $0.mailbox.path == "INBOX" && mail.log.contains("open \($0.internalID)") }
    }
}

@MainActor
@Suite("MacPlanExecutor")
struct MacPlanExecutorTests {
    // MARK: Apps and windows

    @Test func activateVerifiesFrontmost() async {
        let rig = Rig()
        let r = await rig.run(.activateApp(.notes))
        #expect(r.status == .completed)
        #expect(r.observation == .appActive(.notes))
        #expect(rig.windows.front?.bundleID == KnownApp.notes.bundleIdentifier)
    }

    @Test func activateWithoutAccessibilityFails() async {
        let rig = Rig()
        rig.windows.trusted = false
        let r = await rig.run(.activateApp(.notes))
        #expect(r.status == .failed)
        #expect(r.error == .permissionDenied)
    }

    @Test func activateNotConfirmedIsUnverified() async {
        let rig = Rig()
        rig.windows.openActivates = false
        #expect(await rig.run(.activateApp(.notes)).status == .unverified)
    }

    @Test func tileReportsTheVerifiedWindow() async {
        let rig = Rig()
        rig.windows.addWindow(.mail, "Inbox", CGRect(x: 205, y: 151, width: 858, height: 647))
        rig.windows.addWindow(.calendar, "Calendar", CGRect(x: 205, y: 151, width: 858, height: 647))
        let r = await rig.run(.tileWindows(left: .mail, right: .calendar))
        #expect(r.status == .completed)
        guard case .window(let w) = r.observation else { Issue.record("got \(r.observation)"); return }
        #expect(w.app == .mail)
    }

    // MARK: Generic UI

    @Test func clickReportsTheActedLabel() async {
        let rig = Rig()
        let r = await rig.run(.clickElement(label: "the Save button"))
        #expect(r.status == .completed)
        #expect(r.observation == .uiActed(label: "Save"))
    }

    @Test func consequentialButtonsAreNotPressed() async {
        let rig = Rig()
        rig.ui.button("send", "Send", at: CGRect(x: 400, y: 40, width: 60, height: 22))
        let r = await rig.run(.clickElement(label: "send"))
        #expect(r.status == .unsupported)
        #expect(!rig.ui.log.contains("press send"))
    }

    // MARK: Mail (read-only, test-mode scope)

    @Test func singleMatchOpensItInTheTestMailbox() async throws {
        let rig = Rig()
        let r = await rig.run(.readMessage(query: "email from Priya"), channel: .mail)
        #expect(r.status == .completed)
        guard case .messageOpened(let m) = r.observation else { Issue.record("got \(r.observation)"); return }
        #expect(m.sender == "Priya Patel")
        let ref = try #require(MailRefCodec.decode(m.id))
        #expect(ref.mailbox.path == "Import/FlowTest")
        #expect(rig.mail.opens == ["open \(ref.internalID)"])
    }

    @Test func searchesAreForcedIntoTheTestMailbox() async {
        let rig = Rig()
        let r = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail)
        #expect(r.status == .needsClarification)
        guard case .messageCandidates(let c) = r.observation else { Issue.record("got \(r.observation)"); return }
        #expect(c.map(\.sender) == ["Sarah Chen", "Sarah Okafor"], "the inbox Sarah is never offered")
        #expect(c.allSatisfy { $0.epoch == 1 })
        #expect(rig.mail.opens.isEmpty, "nothing opened while ambiguous")
    }

    @Test func chosenCandidateOpensExactlyThatMessage() async throws {
        let rig = Rig()
        let first = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail)
        guard case .messageCandidates(let c) = first.observation else { Issue.record("no candidates"); return }
        let r = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail, bindings: StepBindings(message: c[1]))
        #expect(r.status == .completed)
        guard case .messageOpened(let m) = r.observation else { Issue.record("got \(r.observation)"); return }
        #expect(m.sender == "Sarah Okafor")
        #expect(m.id == c[1].id)
        let ref = try #require(MailRefCodec.decode(c[1].id))
        #expect(rig.mail.opens == ["open \(ref.internalID)"])
    }

    @Test func choiceFromAnOlderSearchIsStale() async {
        let rig = Rig()
        let first = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail)
        guard case .messageCandidates(let c) = first.observation else { Issue.record("no candidates"); return }
        _ = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail)  // newer result set
        let r = await rig.run(.readMessage(query: "Sarah's email"), channel: .mail, bindings: StepBindings(message: c[0]))
        #expect(r.status == .failed)
        #expect(r.error == .staleTarget)
        #expect(r.retrySafe)
        #expect(rig.mail.opens.isEmpty)
    }

    @Test func referencesOutsideTheTestMailboxAreRefused() async {
        let rig = Rig()
        let inbox = rig.mail.messages.values.first { $0.summary.ref.mailbox.path == "INBOX" }!.summary
        let forged = MessageRef(channel: .mail, id: MailRefCodec.encode(inbox.ref), sender: inbox.senderName, subject: inbox.subject, epoch: 0)
        let r = await rig.run(.readMessage(query: "Sarah"), channel: .mail, bindings: StepBindings(message: forged))
        #expect(r.status == .unsupported)
        #expect(rig.mail.opens.isEmpty)
    }

    @Test func namingAnotherMailboxIsRefusedInTestMode() async {
        let rig = Rig()
        let r = await rig.run(.readMessage(query: "Sarah's email in my inbox"), channel: .mail)
        #expect(r.status == .unsupported)
        #expect(!rig.mail.log.contains("search"))
        #expect(await rig.run(.readMessage(query: "sarah's email in the flowtest mailbox"), channel: .mail).status == .needsClarification)
    }

    @Test func noResultsIsAClearFailure() async {
        let rig = Rig()
        let r = await rig.run(.readMessage(query: "email from Nobody"), channel: .mail)
        #expect(r.status == .failed)
        #expect(r.error == .targetNotFound)
        #expect(!r.retrySafe)
        #expect(r.userMessage == "No messages from “Nobody” in mailbox “FlowTest”.")
    }

    @Test func otherChannelsAreNotConnected() async {
        let rig = Rig()
        #expect(await rig.run(.readMessage(query: "Lee's message"), channel: .whatsapp).status == .unsupported)
        #expect(rig.mail.log.isEmpty)
    }

    // MARK: Disabled capabilities

    @Test(arguments: [
        FlowAction.createDraft(recipient: "Sarah", content: "I can meet"),
        .insertText("hello"),
        .replaceText(old: "3", new: "3:30"),
        .requestReview,
        .requestSend,
        .queryCalendar(timeExpression: "tomorrow 4 pm"),
    ])
    func consequentialAndUnbuiltActionsAreUnsupported(action: FlowAction) async {
        let rig = Rig()
        let r = await rig.run(action, channel: .mail)
        #expect(r.status == .unsupported)
        #expect(rig.mail.log.isEmpty, "Mail untouched")
        #expect(rig.ui.log.isEmpty, "UI untouched")
        #expect(rig.windows.mutations == 0)
    }

    @Test func sendSaysNothingWasSent() async {
        #expect(await Rig().run(.requestSend).userMessage == "Sending is disabled in this version. Nothing was sent.")
    }

    // MARK: Cancellation and evidence

    @Test func cancelledRequestDoesNotAct() async {
        let rig = Rig()
        let executor = rig.executor
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await executor.execute(ExecutionRequest(planID: UUID(), stepID: 1, attempt: 1, action: .activateApp(.notes),
                                                           bindings: StepBindings(), expectation: .appFrontmost(.notes)))
        }
        let r = await task.value
        #expect(r.status == .cancelled)
        #expect(rig.windows.front == nil)
    }

    @Test func logRecordsEveryRequestWithoutBodies() async {
        let rig = Rig()
        _ = await rig.run(.activateApp(.notes))
        _ = await rig.run(.readMessage(query: "email from Priya"), channel: .mail)
        _ = await rig.run(.requestSend)
        let log = rig.executor.log
        #expect(log.map(\.action) == ["activate_app", "read_message", "request_send"])
        #expect(log.map(\.status) == [.completed, .completed, .unsupported])
        #expect(!log.contains { $0.observation.contains("Hello there") || $0.userMessage.contains("Hello there") })
    }
}

/// The real TaskSession (FlowRouting + FlowPlanner) driving the real executor over simulated macOS.
@MainActor
@Suite("TaskSession + MacPlanExecutor")
struct TaskSessionIntegrationTests {
    struct NoModel: TracedIntentClassifying {
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))),
                                attempts: [])
        }
    }

    @Test func openNotes() async {
        let rig = Rig()
        let store = IntentRouter(model: NoModel())
        let session = TaskSession(store: store, executor: rig.executor)
        let reply = await session.handle("Open Notes")
        guard case .completed = reply.state else { Issue.record("state \(reply.state) say \(reply.say)"); return }
        #expect(await store.context.activeApp == .notes, "verified state written to the single task-context store")
    }

    @Test func findSarahsEmailChooseAndOpen() async throws {
        let rig = Rig()
        let store = IntentRouter(model: NoModel())
        let session = TaskSession(store: store, executor: rig.executor)
        let ask = await session.handle("Find Sarah's email")
        guard case .awaitingChoice(let q) = ask.state else {
            for e in rig.executor.log { print("DIAG log: \(e.action) \(e.status) | \(e.observation) | \(e.userMessage)") }
            print("DIAG mail: \(rig.mail.log)")
            Issue.record("state \(ask.state) say \(ask.say)")
            return
        }
        #expect(q.options.count == 2)
        #expect(rig.mail.opens.isEmpty)

        let reply = await session.handle("the second one")
        guard case .completed = reply.state else {
            for e in rig.executor.log { print("DIAG log: \(e.action) \(e.status) | \(e.observation) | \(e.userMessage)") }
            Issue.record("state \(reply.state) say \(reply.say)")
            return
        }
        let selected = try #require(await store.context.selectedMessage)
        #expect(selected.sender == "Sarah Okafor")
        #expect(rig.mail.opens.count == 1)
        #expect(!rig.realInboxTouched)
    }

    @Test func sendStaysDisabledEndToEnd() async {
        let rig = Rig()
        let session = TaskSession(store: IntentRouter(model: NoModel()), executor: rig.executor)
        _ = await session.handle("send it")
        #expect(!rig.executor.log.contains { $0.action == "request_send" && $0.status == .completed })
    }
}
