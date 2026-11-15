import AppKit
import ApplicationServices
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

/// Live T-023B: real router + planner (model disabled) → real executor (editing enabled for
/// this test only) → real Mail, on the synthetic FlowTest mailbox. Nothing is sent. Every
/// draft body starts "FLOWTEST SAFE:" so `TestDraftCleanup` can close it afterwards.
///
/// **Not run yet** (the user chose simulated-only for this milestone). Opt in:
/// `FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 FLOW_LIVE_EDIT=1 swift test --filter LiveDraftEditingTests`
@MainActor
@Suite("Live draft editing (FlowTest only, never sent)",
       .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_AX"] == "1"
                    && ProcessInfo.processInfo.environment["FLOW_LIVE_MAIL"] == "1"
                    && ProcessInfo.processInfo.environment["FLOW_LIVE_EDIT"] == "1"),
       .serialized)
struct LiveDraftEditingTests {
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
            configuration: ExecutorConfiguration(mailScope: .testMailbox("FlowTest"), allowMailDraftEditing: true))
        let store = IntentRouter(model: LiveReplyDraftTests.NoModel())
        return (TaskSession(store: store, executor: executor), store, executor)
    }

    func log(_ executor: MacPlanExecutor) {
        for e in executor.log { print("LIVE-EDIT \(e.action) → \(e.status.rawValue) · \(e.observation) · \(e.userMessage)") }
    }

    /// Probe: what Mail's compose body exposes to Accessibility (read-only; changes nothing).
    @Test func probeComposeBodyAccessibility() async throws {
        try #require(AccessibilityPermission.isTrusted)
        _ = await TestDraftCleanup.run()
        let (session, store, _) = make()
        try await LiveReplyDraftTests().openChen(session, store)
        _ = await session.handle("Reply saying FLOWTEST SAFE: probe")
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: JXAMailBackend.bundleID).first else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
        }
        func settable(_ e: AXUIElement, _ n: String) -> Bool {
            var b: DarwinBoolean = false
            return AXUIElementIsAttributeSettable(e, n as CFString, &b) == .success && b.boolValue
        }
        func walk(_ e: AXUIElement, _ depth: Int) {
            let role = attr(e, kAXRoleAttribute) as? String ?? "?"
            if role == "AXWebArea" || role == "AXTextArea" {
                print("LIVE-EDIT probe \(role) desc=\(attr(e, kAXDescriptionAttribute) as? String ?? "") "
                      + "value settable=\(settable(e, kAXValueAttribute)) selectedRange settable=\(settable(e, kAXSelectedTextRangeAttribute)) "
                      + "selectedText settable=\(settable(e, kAXSelectedTextAttribute))")
            }
            guard depth < 18 else { return }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
        }
        for w in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] where (attr(w, kAXTitleAttribute) as? String) == LiveReplyDraftTests.replySubject {
            walk(w, 0)
        }
        print("LIVE-EDIT cleanup after: \(await TestDraftCleanup.run())")
    }

    @Test func acceptanceSequenceOnRealMail() async throws {
        try #require(AccessibilityPermission.isTrusted)
        print("LIVE-EDIT cleanup before: \(await TestDraftCleanup.run())")
        let before = await TestDraftCleanup.counts()
        let (session, store, executor) = make()
        try await LiveReplyDraftTests().openChen(session, store)
        _ = await session.handle("Reply saying FLOWTEST SAFE: I can meet at 3:30.")
        let created = try #require(await store.context.draft)

        for (utterance, expected) in [
            ("Actually, change 3:30 to 4.", "FLOWTEST SAFE: I can meet at 4"),
            ("Also say I'll send the details tonight.", "I'll send the details tonight."),
        ] {
            let r = await session.handle(utterance)
            log(executor)
            guard case .completed = r.state else { Issue.record("\(utterance): \(r.state) \(r.say)"); return }
            let views = AXMailComposeInspector().compose(titled: LiveReplyDraftTests.replySubject)
            #expect(views.count == 1)
            #expect(views.first.map { ComposeParser.normalize($0.body).contains(expected) } == true, "on screen: \(expected)")
            #expect(views.first?.to == ["Sarah Chen"] && views.first?.cc.isEmpty == true)
        }
        let review = await session.handle("What does the draft say?")
        #expect(review.say.contains { $0.contains("I'll send the details tonight") })
        let undo = await session.handle("Undo that last change.")
        log(executor)
        guard case .completed = undo.state else { Issue.record("undo: \(undo.state) \(undo.say)"); return }
        let after = try #require(await store.context.draft)
        #expect(after.id == created.id && after.recipients == created.recipients && after.subject == created.subject)
        let counts = await TestDraftCleanup.counts()
        #expect(counts.open == before.open + 1, "still exactly one reply: edited in place")
        #expect(counts.sent == before.sent, "nothing sent")
        print("LIVE-EDIT cleanup after: \(await TestDraftCleanup.run())")
    }
}
