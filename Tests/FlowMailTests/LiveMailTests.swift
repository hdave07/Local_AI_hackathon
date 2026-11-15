import FlowAX
@testable import FlowMail
import Foundation
import Testing

/// Live Apple Mail tests. Opt in: `FLOW_LIVE_MAIL=1 swift test --filter FlowMailTests`.
///
/// Uses ONLY the synthetic "FlowTest" mailbox imported from fixtures/mail/FlowTest.mbox
/// (fictitious example.invalid messages). Every query is scoped to that mailbox and every
/// returned reference is asserted to live in it, so real messages are never opened.
/// Read-only: nothing is sent, deleted, moved or flagged. Opened viewer windows are closed.
/// Requires Automation consent for the test runner's terminal/IDE to control Mail, and
/// Accessibility permission for on-screen verification.
@MainActor
@Suite("Live Apple Mail (FlowTest mailbox only)",
       .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_MAIL"] == "1"), .serialized)
struct LiveMailTests {
    static let mailbox = "FlowTest"

    func makeController() -> MailController {
        MailController(backend: JXAMailBackend(), verifier: AXMailDisplayVerifier())
    }

    func query(sender: String? = nil, subject: String? = nil) -> MailQuery {
        MailQuery(sender: sender, subject: subject, mailbox: Self.mailbox)
    }

    /// Guard: results must come from the synthetic mailbox only.
    func assertSynthetic(_ messages: [MailMessageSummary]) {
        for m in messages {
            #expect(m.ref.mailbox.account == nil && m.ref.mailbox.path.hasSuffix("FlowTest"), "non-fixture message returned")
            #expect(m.senderAddress.hasSuffix("@example.invalid"))
        }
    }

    func log(_ r: MailResult) { print("LIVE-MAIL\n\(r.report)") }

    /// Closes only the viewer windows these tests opened (titles start with "[FlowTest]").
    func closeFixtureWindows() async {
        _ = try? await OSAScriptRunner().run(javaScript: """
            function run(argv) {
              const Mail = Application('com.apple.mail');
              for (const w of Mail.windows()) { try { if (w.name().indexOf('[FlowTest]') === 0) w.close(); } catch (e) {} }
              return '';
            }
            """, argument: "{}", timeout: .seconds(10))
    }

    @Test func mailIsReadyAndFixtureImported() async throws {
        let mail = makeController()
        let status = await mail.perform(.status(requestPermission: true))
        log(status)
        try #require(status.status == .completed, "Mail must be configured and Automation allowed")
        let all = await mail.perform(.find(MailQuery(subject: "[FlowTest]", mailbox: Self.mailbox)))
        try #require(all.totalMatches == 5, "import fixtures/mail/FlowTest.mbox into Mail first")
        assertSynthetic(all.messages)
    }

    @Test func findEmailFromSpecifiedSender() async {
        let r = await makeController().perform(.find(query(sender: "Priya")))
        log(r)
        #expect(r.status == .completed)
        #expect(r.messages.count == 1)
        #expect(r.messages.first?.subject == "[FlowTest] Project budget review")
        #expect(r.messages.first?.senderName == "Priya Patel")
        #expect(r.messages.first?.dateReceived == ISO8601DateFormatter().date(from: "2026-11-11T21:45:00Z"))
        #expect(r.messages.first?.ref.messageID == "flowtest-003@example.invalid")
        assertSynthetic(r.messages)
    }

    @Test func searchBySubject() async {
        let r = await makeController().perform(.find(query(subject: "launch checklist")))
        log(r)
        #expect(r.messages.map(\.ref.messageID) == ["flowtest-004@example.invalid"])
        assertSynthetic(r.messages)
    }

    @Test func multipleMatchesAskTheUserToChoose() async {
        let r = await makeController().perform(.open(query(sender: "sarah")))
        log(r)
        #expect(r.status == .needsClarification)
        #expect(r.clarification?.options.count == 3)
        #expect(r.userMessage.contains("2 different senders"))
        #expect(r.opened == nil, "nothing opened while ambiguous")
        assertSynthetic(r.messages)
    }

    @Test func openTheCorrectEmailInMail() async {
        let mail = makeController()
        _ = await mail.perform(.find(query(sender: "sarah")))
        let options = mail.candidates
        let okafor = options.firstIndex { $0.senderName == "Sarah Okafor" }.map { $0 + 1 }
        #expect(okafor != nil)
        let r = await mail.perform(.choose(okafor ?? 1))
        log(r)
        #expect(r.status == .completed)
        #expect(r.opened?.ref.messageID == "flowtest-002@example.invalid")
        #expect(r.observation == MailDisplayObservation(scriptedWindowMatches: true, visibleWindowMatches: true, bodyVisible: true))
        #expect(mail.activeMessage?.ref.messageID == "flowtest-002@example.invalid")
        await closeFixtureWindows()
    }

    @Test func readItsContent() async throws {
        let mail = makeController()
        let r = await mail.perform(.read(query(sender: "okafor")))
        log(r)
        #expect(r.status == .completed)
        let body = try #require(r.content?.body)
        #expect(body.contains("Are you free for lunch on Friday?"))
        #expect(!body.contains("Message-ID") && !body.contains("X-Flow-Fixture") && !body.contains("example.invalid"),
                "no headers or hidden metadata in the body")
        let again = await mail.perform(.readActive)
        #expect(again.content?.body == body)
        await closeFixtureWindows()
    }

    @Test func clearNoResultsResponse() async {
        let r = await makeController().perform(.find(query(sender: "nobody-flowtest-zz")))
        log(r)
        #expect(r.status == .completed)
        #expect(r.messages.isEmpty)
        #expect(r.userMessage == "No messages from “nobody-flowtest-zz” in mailbox “FlowTest”.")
    }

    @Test func staleReferencesAreRejected() async throws {
        let mail = makeController()
        let found = await mail.perform(.find(query(sender: "Diego")))
        let ref = try #require(found.messages.first?.ref)
        assertSynthetic(found.messages)

        // A reference whose Message-ID no longer matches what Mail holds at that id.
        let swapped = MailMessageRef(messageID: "flowtest-001@example.invalid", mailbox: ref.mailbox, internalID: ref.internalID)
        let changed = await mail.perform(.openMessage(swapped))
        log(changed)
        guard case .referenceChanged = changed.error else { Issue.record("got \(String(describing: changed.error))"); return }

        // A reference to a message id that no longer exists in that mailbox.
        let gone = MailMessageRef(messageID: ref.messageID, mailbox: ref.mailbox, internalID: 999_999_999)
        let missing = await mail.perform(.readMessage(gone))
        log(missing)
        #expect(missing.error == .messageGone)

        // A reference into a mailbox that doesn't exist.
        let noBox = MailMessageRef(messageID: ref.messageID, mailbox: MailboxRef(account: nil, path: "Import/NoSuchBox"), internalID: ref.internalID)
        #expect(await mail.perform(.openMessage(noBox)).error == .messageGone)
        #expect(mail.activeMessage == nil, "nothing was opened")
    }
}
