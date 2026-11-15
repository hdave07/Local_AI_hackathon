import AppKit
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

/// Live acceptance tests: validated plans from the real router and planner, executed by the
/// real executor on this Mac. Notes, plus the synthetic FlowTest mailbox only (test-mode
/// scope). Opt in: `FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 swift test --filter LiveExecutorTests`.
@MainActor
@Suite("Live real executor (Notes + FlowTest mailbox)",
       .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"
                    && ProcessInfo.processInfo.environment["FLOW_LIVE_MAIL"] == "1"),
       .serialized)
struct LiveExecutorTests {
    struct NoModel: TracedIntentClassifying {
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "model disabled", source: .model(id: "none"))),
                                attempts: [])
        }
    }

    func makeSession() -> (TaskSession, IntentRouter, MacPlanExecutor) {
        let windows = AXWindowBackend()
        var nav = UINavigator.Configuration()
        nav.bringTargetToFront = true
        let executor = MacPlanExecutor(
            window: WindowController(backend: windows),
            navigator: UINavigator(backend: AXUIBackend(frontmost: { windows.frontmostApp() }), configuration: nav),
            mail: MailController(backend: JXAMailBackend(), verifier: AXMailDisplayVerifier()),
            configuration: ExecutorConfiguration(mailScope: .testMailbox("FlowTest")))
        let store = IntentRouter(model: NoModel())  // deterministic routing only: no model output reaches the executor
        return (TaskSession(store: store, executor: executor), store, executor)
    }

    func closeFixtureWindows() async {
        _ = try? await OSAScriptRunner().run(javaScript: """
            function run(argv) {
              const Mail = Application('com.apple.mail');
              for (const w of Mail.windows()) { try { if (w.name().indexOf('[FlowTest]') === 0) w.close(); } catch (e) {} }
              return '';
            }
            """, argument: "{}", timeout: .seconds(10))
    }

    func log(_ executor: MacPlanExecutor) {
        for e in executor.log { print("LIVE-EXEC \(e.action) → \(e.status.rawValue) · \(e.observation) · \(e.userMessage)") }
    }

    @Test func milestone1OpenNotesVerifiedFrontmost() async throws {
        try #require(AccessibilityPermission.isTrusted)
        let (session, store, executor) = makeSession()
        let reply = await session.handle("Open Notes")
        log(executor)
        guard case .completed = reply.state else { Issue.record("state \(reply.state) say \(reply.say)"); return }
        #expect(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == KnownApp.notes.bundleIdentifier)
        #expect(executor.log.last?.observation == "app active: Notes")
        #expect(await store.context.activeApp == .notes)
    }

    @Test func milestone2TwoSarahsChooseOpenAndVerify() async throws {
        try #require(AccessibilityPermission.isTrusted)
        let (session, store, executor) = makeSession()
        let ask = await session.handle("Find Sarah's email")
        guard case .awaitingChoice(let q) = ask.state else { Issue.record("state \(ask.state) say \(ask.say)"); log(executor); return }
        #expect(q.candidates.count == 3)
        #expect(q.candidates.allSatisfy { $0.subject.hasPrefix("[FlowTest]") && ($0.senderAddress ?? "").hasSuffix("@example.invalid") },
                "only synthetic messages are offered")
        #expect(Set(q.candidates.map(\.sender)) == ["Sarah Chen", "Sarah Okafor"], "two different Sarahs")

        let done = await session.handle("Sarah Okafor")
        log(executor)
        guard case .completed = done.state else { Issue.record("state \(done.state) say \(done.say)"); return }
        let opened = try #require(await store.context.selectedMessage)
        #expect(opened.subject == "[FlowTest] Lunch on Friday?")
        // FlowMail reports `completed` only when the window title AND the start of the body are on screen.
        #expect(executor.log.last?.status == .completed)
        #expect(executor.log.last?.observation.contains("Sarah Okafor") == true)
        await closeFixtureWindows()
    }

    @Test func sendAndDraftStayDisabledLive() async {
        let (session, _, executor) = makeSession()
        _ = await session.handle("reply to it saying test only")
        _ = await session.handle("send it")
        log(executor)
        #expect(!executor.log.contains { ["create_draft", "request_send"].contains($0.action) && $0.status == .completed })
    }
}
