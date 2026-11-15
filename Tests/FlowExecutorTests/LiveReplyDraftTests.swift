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

/// Test-only cleanup of drafts these tests create (never part of Flow.app, which has no delete
/// capability). Only drafts matching ALL of: subject "Re: [FlowTest]…", every recipient
/// @example.invalid, body starting "FLOWTEST SAFE:" are closed unsaved and their autosaved
/// copies moved to Trash. Anything else is left alone.
enum TestDraftCleanup {
    static let marker = "FLOWTEST SAFE:"

    @discardableResult
    static func run() async -> String {
        let script = """
            function run(argv) {
              const Mail = Application('com.apple.mail');
              const ours = (subject, to, body) => subject.indexOf('Re: [FlowTest]') === 0 && to.length > 0
                && to.every(a => a.endsWith('@example.invalid')) && String(body || '').trim().indexOf('\(marker)') === 0;
              const addrs = l => l.map(r => { try { return r.address().toLowerCase(); } catch (e) { return ''; } });
              let closed = 0, deleted = 0;
              for (const o of Mail.outgoingMessages()) {
                try { if (ours(o.subject(), addrs(o.toRecipients()), o.content())) { o.close({ saving: 'no' }); closed++; } } catch (e) {}
              }
              delay(1.5);
              try {
                for (const m of Mail.draftsMailbox().messages.whose({ subject: { _beginsWith: 'Re: [FlowTest]' } })()) {
                  if (ours(m.subject(), addrs(m.toRecipients()), m.content())) { Mail.delete(m); deleted++; }
                }
              } catch (e) {}
              return JSON.stringify({ closed: closed, deleted: deleted });
            }
            """
        let out = (try? await OSAScriptRunner().run(javaScript: script, argument: "{}", timeout: .seconds(20))) ?? Data()
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    /// Open (unsent) replies to FlowTest messages, and FlowTest messages in Sent (must stay 0).
    static func counts() async -> (open: Int, sent: Int) {
        let script = """
            function run(argv) {
              const Mail = Application('com.apple.mail');
              const open = Mail.outgoingMessages().filter(o => { try { return o.subject().indexOf('Re: [FlowTest]') === 0; } catch (e) { return false; } }).length;
              let sent = 0;
              try { sent = Mail.sentMailbox().messages.whose({ subject: { _contains: '[FlowTest]' } })().length; } catch (e) {}
              return JSON.stringify({ open: open, sent: sent });
            }
            """
        guard let data = try? await OSAScriptRunner().run(javaScript: script, argument: "{}", timeout: .seconds(20)),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return (-1, -1) }
        return (o["open"] ?? -1, o["sent"] ?? -1)
    }

    /// Simulates the user adding a recipient in the compose window (an edit Flow didn't make).
    static func addRecipient(_ address: String) async {
        _ = try? await OSAScriptRunner().run(javaScript: """
            function run(argv) {
              const Mail = Application('com.apple.mail');
              const o = Mail.outgoingMessages().filter(o => o.subject() === 'Re: [FlowTest] Launch checklist')[0];
              o.toRecipients.push(Mail.ToRecipient({ address: JSON.parse(argv[0]).address }));
              return '';
            }
            """, argument: "{\"address\":\"\(address)\"}", timeout: .seconds(20))
    }
}

/// Live T-023A tests: real router + planner (model disabled) → real executor → real Mail, on
/// synthetic FlowTest messages only. Nothing is sent. Opt in:
/// `FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 swift test --filter LiveReplyDraftTests`.
@MainActor
@Suite("Live reply drafts (FlowTest only, never sent)",
       .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"
                    && ProcessInfo.processInfo.environment["FLOW_LIVE_MAIL"] == "1"),
       .serialized)
struct LiveReplyDraftTests {
    struct NoModel: TracedIntentClassifying {
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "model disabled", source: .model(id: "none"))),
                                attempts: [])
        }
    }

    func make() -> (TaskSession, IntentRouter, MacPlanExecutor) {
        let windows = AXWindowBackend()
        let jxa = JXAMailBackend()
        var nav = UINavigator.Configuration()
        nav.bringTargetToFront = true
        let executor = MacPlanExecutor(
            window: WindowController(backend: windows),
            navigator: UINavigator(backend: AXUIBackend(frontmost: { windows.frontmostApp() }), configuration: nav),
            mail: MailController(backend: jxa, verifier: AXMailDisplayVerifier()),
            drafts: MailDraftController(mail: jxa, backend: jxa, inspector: AXMailComposeInspector()),
            configuration: ExecutorConfiguration(mailScope: .testMailbox("FlowTest")))
        let store = IntentRouter(model: NoModel())
        return (TaskSession(store: store, executor: executor), store, executor)
    }

    /// Tests reply to Sarah Chen's "Launch checklist" (third candidate), so they never collide
    /// with a reply the user may have open to "Meeting tomorrow".
    static let subject = "[FlowTest] Launch checklist"
    static let replySubject = "Re: [FlowTest] Launch checklist"

    func openChen(_ session: TaskSession, _ store: IntentRouter) async throws {
        guard case .awaitingChoice = await session.handle("Find Sarah's email").state else { throw CancellationError() }
        guard case .completed = await session.handle("the third one").state else { throw CancellationError() }
        try #require(await store.context.selectedMessage?.subject == Self.subject)
    }

    func log(_ executor: MacPlanExecutor) {
        for e in executor.log { print("LIVE-DRAFT \(e.action) → \(e.status.rawValue) · \(e.observation) · \(e.userMessage)") }
    }

    @Test func acceptanceReplySayingIsAddressedThreadedAndUnsent() async throws {
        try #require(AccessibilityPermission.isTrusted)
        print("LIVE-DRAFT cleanup before: \(await TestDraftCleanup.run())")
        let before = await TestDraftCleanup.counts()
        let (session, store, executor) = make()
        try await openChen(session, store)

        let reply = await session.handle("Reply saying FLOWTEST SAFE: I can meet at 3")
        log(executor)
        guard case .completed = reply.state else { Issue.record("state \(reply.state) say \(reply.say)"); return }
        let draft = try #require(await store.context.draft)
        #expect(draft.recipients == ["sarah.chen@example.invalid"])
        #expect(draft.subject == Self.replySubject)
        #expect(draft.body.contains("FLOWTEST SAFE: I can meet at 3"))
        #expect(draft.inReplyTo == (await store.context.selectedMessage)?.id)

        // Independent on-screen check, separate from the executor's own verification.
        let views = AXMailComposeInspector().compose(titled: Self.replySubject)
        #expect(views.count == 1)
        #expect(views.first?.to == ["Sarah Chen"])
        #expect(views.first?.cc.isEmpty == true)
        #expect(views.first.map { ComposeParser.normalize($0.body).contains("FLOWTEST SAFE: I can meet at 3") } == true)
        let counts = await TestDraftCleanup.counts()
        #expect(counts.open == before.open + 1, "exactly one new unsent reply")
        #expect(counts.sent == before.sent, "nothing sent")
        print("LIVE-DRAFT cleanup after: \(await TestDraftCleanup.run())")
    }

    @Test func reviewAndExternalEditBumpsTheVersion() async throws {
        try #require(AccessibilityPermission.isTrusted)
        _ = await TestDraftCleanup.run()
        let (session, store, executor) = make()
        try await openChen(session, store)
        _ = await session.handle("Reply saying FLOWTEST SAFE: review test and show it to me")
        #expect(await store.context.reviewedDraftVersion == 1)

        await TestDraftCleanup.addRecipient("someone.else@example.invalid")  // edit made outside Flow
        let r = await session.handle("show me the draft")
        log(executor)
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        let draft = try #require(await store.context.draft)
        #expect(draft.version == 2)
        #expect(draft.recipients.contains("someone.else@example.invalid"))
        #expect(await store.context.reviewedDraftVersion == 2)
        print("LIVE-DRAFT cleanup after: \(await TestDraftCleanup.run())")
    }

    @Test func twoTurnReplyAndNoDuplicate() async throws {
        try #require(AccessibilityPermission.isTrusted)
        _ = await TestDraftCleanup.run()
        let before = await TestDraftCleanup.counts()
        let (session, store, executor) = make()
        try await openChen(session, store)
        let ask = await session.handle("reply to it")
        #expect(ask.say == ["What should the reply to Sarah Chen say?"])
        #expect(await TestDraftCleanup.counts().open == before.open, "nothing created before the content is known")
        let done = await session.handle("FLOWTEST SAFE: two turn reply")
        guard case .completed = done.state else { Issue.record("state \(done.state) say \(done.say)"); return }
        #expect(await store.context.draft?.body.contains("FLOWTEST SAFE: two turn reply") == true)

        // A second, different reply to the same message while one is open is refused, not duplicated.
        let second = await session.handle("reply to it saying FLOWTEST SAFE: second reply")
        log(executor)
        guard case .stopped = second.state else { Issue.record("state \(second.state)"); return }
        #expect(await TestDraftCleanup.counts().open == before.open + 1)
        print("LIVE-DRAFT cleanup after: \(await TestDraftCleanup.run())")
    }

    @Test func replyWhileChoosingAndSendStayNoOps() async throws {
        try #require(AccessibilityPermission.isTrusted)
        _ = await TestDraftCleanup.run()
        let before = await TestDraftCleanup.counts()
        let (session, store, executor) = make()
        guard case .awaitingChoice = await session.handle("Find Sarah's email").state else { Issue.record("no question"); return }
        _ = await session.handle("Reply saying FLOWTEST SAFE: should not exist")
        #expect(await TestDraftCleanup.counts().open == before.open, "no draft without a chosen message")

        _ = await session.handle("the third one")
        _ = await session.handle("Reply saying FLOWTEST SAFE: send test and show it to me")
        _ = await session.handle("send it")
        _ = await session.handle("yes")
        log(executor)
        #expect(executor.log.contains { $0.action == "request_send" && $0.status == .unsupported })
        let counts = await TestDraftCleanup.counts()
        #expect(counts.open == before.open + 1, "draft still open, unsent")
        #expect(counts.sent == before.sent)
        _ = store
        print("LIVE-DRAFT cleanup after: \(await TestDraftCleanup.run())")
    }
}
