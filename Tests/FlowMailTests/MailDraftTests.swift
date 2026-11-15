import FlowAX
@testable import FlowMail
import Foundation
import Testing

/// Simulated Mail compose behaviour: open drafts, what Mail would address a reply to,
/// and what Accessibility shows.
@MainActor
final class FakeDraftBackend: MailDraftBackend {
    struct Open {
        var subject: String
        var to: [String]
        var cc: [String] = []
        var bcc: [String] = []
        var body: String
        var visible = true
    }

    let mail: FakeMailBackend
    var open: [Open] = []
    /// What Mail would put in To (e.g. a Reply-To address); nil = the original sender.
    var replyTo: [String]?
    var replyCc: [String] = []
    var setContentWorks = true
    var createError: MailError?
    /// With `createError`: the draft was opened anyway (unknown outcome).
    var openedDespiteError = false
    var createDelay: Duration?
    private(set) var creates = 0
    private(set) var log: [String] = []

    init(mail: FakeMailBackend) { self.mail = mail }

    func createReplyDraft(_ ref: MailMessageRef, recipient: String, content: String) async throws(MailError) -> ReplyCreation {
        log.append("create")
        if let createDelay { try? await Task.sleep(for: createDelay) }
        guard let original = mail.messages[ref]?.summary else { throw .messageGone }
        let subject = "Re: \(original.subject)"
        let existing = open.filter { $0.subject == subject }
        if !existing.isEmpty { return .existing(subject: subject, drafts: existing.map { OpenDraftInfo(to: $0.to, cc: $0.cc, bcc: $0.bcc) }) }
        if let createError {
            if openedDespiteError { creates += 1; open.append(Open(subject: subject, to: [recipient], body: content)) }
            throw createError
        }
        let to = replyTo ?? [recipient]
        if to != [recipient] || !replyCc.isEmpty { return .mismatch(to: to, cc: replyCc, bcc: []) }
        creates += 1
        open.append(Open(subject: subject, to: to, body: setContentWorks ? content : ""))
        return .created(subject: subject, to: to, cc: [], bcc: [], contentSet: setContentWorks, windowShown: true)
    }

    func openDrafts(subject: String) async throws(MailError) -> [OpenDraftInfo] {
        open.filter { $0.subject == subject }.map { OpenDraftInfo(to: $0.to, cc: $0.cc, bcc: $0.bcc) }
    }

    func showDraft(subject: String) async throws(MailError) -> Int {
        log.append("show")
        return open.filter { $0.subject == subject }.count
    }
}

@MainActor
final class FakeComposeInspector: MailComposeInspecting {
    let backend: FakeDraftBackend
    var extraToTokens: [String] = []
    init(backend: FakeDraftBackend) { self.backend = backend }

    func compose(titled subject: String) -> [MailComposeView] {
        backend.open.filter { $0.subject == subject && $0.visible }.map {
            MailComposeView(title: $0.subject, to: $0.to + extraToTokens, cc: $0.cc, subject: $0.subject, body: $0.body)
        }
    }
}

@MainActor
struct DraftRig {
    let mail = FakeMailBackend()
    let backend: FakeDraftBackend
    let inspector: FakeComposeInspector
    let drafts: MailDraftController
    let chen: MailMessageRef

    init(withInspector: Bool = true) {
        chen = mail.add("Sarah Chen", "sarah.chen@example.invalid", "[FlowTest] Meeting tomorrow", mailbox: "Import/FlowTest", account: nil)
        backend = FakeDraftBackend(mail: mail)
        inspector = FakeComposeInspector(backend: backend)
        var c = MailDraftController.Configuration()
        c.verifyTimeout = .milliseconds(30)
        c.pollInterval = .milliseconds(5)
        drafts = MailDraftController(mail: mail, backend: backend, inspector: withInspector ? inspector : nil, configuration: c)
    }

    func create(_ text: String = "FLOWTEST SAFE: I can meet at 3", key: String = "plan#1") async -> MailDraftResult {
        await drafts.createReply(to: chen, content: text, key: key)
    }
}

@Suite("Compose parsing")
struct ComposeParserTests {
    /// The Mail 16 compose tree observed live (probe, 2026-11-14).
    static let window = ComposeNode(role: "AXWindow", children: [
        ComposeNode(role: "AXStaticText", identifier: "lablel_to", value: "To:"),
        ComposeNode(role: "AXTextField", identifier: "Mail.toField", value: "\u{FFFC}", children: [
            ComposeNode(role: "AXTextField", subrole: "AXTextAttachment", value: "Sarah Chen"),
        ]),
        ComposeNode(role: "AXTextField", identifier: "Mail.ccField"),
        ComposeNode(role: "AXTextField", identifier: "Mail.subjectField", value: "Re: [FlowTest] Meeting tomorrow"),
        ComposeNode(role: "AXScrollArea", children: [
            ComposeNode(role: "AXWebArea", description: "message body", children: [
                ComposeNode(role: "AXGroup", children: [
                    ComposeNode(role: "AXStaticText", value: "FLOWTEST SAFE: I can meet at 3"),
                    ComposeNode(role: "AXStaticText", value: " "),
                ]),
            ]),
        ]),
        ComposeNode(role: "AXButton", identifier: "send", description: "Send"),
    ])

    @Test func parsesTheLiveLayout() {
        let v = ComposeParser.parse(title: "Re: [FlowTest] Meeting tomorrow", window: Self.window)
        #expect(v.to == ["Sarah Chen"])
        #expect(v.cc.isEmpty)
        #expect(v.subject == "Re: [FlowTest] Meeting tomorrow")
        #expect(v.body == "FLOWTEST SAFE: I can meet at 3")
    }

    @Test func typedRecipientsWithoutTokens() {
        let w = ComposeNode(role: "AXWindow", children: [ComposeNode(role: "AXTextField", identifier: "Mail.ccField", value: "a@x.invalid, b@y.invalid")])
        #expect(ComposeParser.parse(title: "t", window: w).cc == ["a@x.invalid", "b@y.invalid"])
    }

    @Test func normalization() {
        #expect(ComposeParser.normalize("  I  can\u{00A0}meet \n\n\n at 3 \u{FFFC} ") == "I can meet\n\nat 3")
    }
}

@MainActor
@Suite("MailDraftController")
struct MailDraftControllerTests {
    @Test func createsAVerifiedReplyToTheSenderOnly() async throws {
        let rig = DraftRig()
        let r = await rig.create()
        #expect(r.status == .completed)
        let d = try #require(r.draft)
        #expect(d.recipients == ["sarah.chen@example.invalid"])
        #expect(d.subject == "Re: [FlowTest] Meeting tomorrow")
        #expect(d.body == "FLOWTEST SAFE: I can meet at 3")
        #expect(d.version == 1)
        #expect(d.inReplyTo == rig.chen)
        #expect(rig.backend.creates == 1)
    }

    @Test func oneDraftPerPlanStep() async {
        let rig = DraftRig()
        let first = await rig.create()
        let again = await rig.create()
        #expect(again.draft?.id == first.draft?.id)
        #expect(rig.backend.creates == 1)
        #expect(again.evidence.contains { $0.contains("not duplicated") })
    }

    @Test(arguments: [(["boss@example.invalid"], [String]()), (["sarah.chen@example.invalid"], ["team@example.invalid"])])
    func recipientMismatchIsRefused(to: [String], cc: [String]) async {
        let rig = DraftRig()
        rig.backend.replyTo = to
        rig.backend.replyCc = cc
        let r = await rig.create()
        #expect(r.status == .failed)
        guard case .recipientMismatch(let expected, _) = r.error else { Issue.record("got \(String(describing: r.error))"); return }
        #expect(expected == "sarah.chen@example.invalid")
        #expect(rig.backend.open.isEmpty, "the unseen draft was discarded, nothing left open")
    }

    @Test func matchingOpenReplyIsReusedNotDuplicated() async {
        let rig = DraftRig()
        rig.backend.open = [.init(subject: "Re: [FlowTest] Meeting tomorrow", to: ["sarah.chen@example.invalid"], body: "FLOWTEST SAFE: I can meet at 3")]
        let r = await rig.create()
        #expect(r.status == .completed)
        #expect(rig.backend.creates == 0)
        #expect(rig.backend.open.count == 1)
    }

    @Test func differentOpenReplyIsRefused() async {
        let rig = DraftRig()
        rig.backend.open = [.init(subject: "Re: [FlowTest] Meeting tomorrow", to: ["sarah.chen@example.invalid"], body: "something else")]
        let r = await rig.create()
        #expect(r.error == .draftAlreadyOpen)
        #expect(rig.backend.creates == 0)
    }

    @Test func timeoutNeverLeadsToADuplicate() async {
        let rig = DraftRig()
        rig.backend.createError = .timedOut
        rig.backend.openedDespiteError = true
        let first = await rig.create(key: "plan#1")
        #expect(first.status == .unverified)
        rig.backend.createError = nil
        let retry = await rig.create(key: "plan#1")
        #expect(retry.status == .completed, "the open draft from the uncertain attempt is reused")
        #expect(rig.backend.open.count == 1)
        #expect(rig.backend.creates == 1)
    }

    @Test func staleOriginalIsNotRepliedTo() async {
        let rig = DraftRig()
        rig.mail.messages[rig.chen] = nil
        #expect(await rig.create().error == .messageGone)
        let rig2 = DraftRig()
        rig2.mail.edit(rig2.chen, messageID: "other@example.invalid")
        guard case .referenceChanged = await rig2.create().error else { Issue.record("expected referenceChanged"); return }
        #expect(rig.backend.log.isEmpty && rig2.backend.log.isEmpty)
    }

    @Test func wrongTextOnScreenIsUnverified() async {
        let rig = DraftRig()
        rig.backend.setContentWorks = false
        #expect(await rig.create().status == .unverified)
    }

    @Test func extraRecipientOnScreenIsUnverified() async {
        let rig = DraftRig()
        rig.inspector.extraToTokens = ["Team"]
        #expect(await rig.create().status == .unverified)
    }

    @Test func noAccessibilityMeansUnverified() async {
        #expect(await DraftRig(withInspector: false).create().status == .unverified)
    }

    @Test func emptyContentAndNoAddress() async {
        let rig = DraftRig()
        #expect(await rig.create("   ").error == .emptyContent)
        #expect(rig.backend.log.isEmpty)
    }

    @Test func cancelledBeforeCreating() async {
        let rig = DraftRig()
        let drafts = rig.drafts, chen = rig.chen
        let task = Task { () -> MailDraftResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return await drafts.createReply(to: chen, content: "FLOWTEST SAFE: hi", key: "k")
        }
        #expect(await task.value.draft == nil)
        #expect(rig.backend.creates == 0)
    }

    // MARK: Live state and review

    @Test func unchangedDraftKeepsItsVersion() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        let r = await rig.drafts.refresh(d.id, present: true)
        #expect(r.status == .completed)
        #expect(r.draft?.version == 1)
        #expect(rig.backend.log.contains("show"))
    }

    @Test func externalBodyEditBumpsTheVersion() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        rig.backend.open[0].body = "FLOWTEST SAFE: I can meet at 3:30"
        let r = await rig.drafts.refresh(d.id, present: true)
        #expect(r.draft?.version == 2)
        #expect(r.draft?.body == "FLOWTEST SAFE: I can meet at 3:30")
        #expect(r.userMessage.contains("changed outside Flow"))
    }

    @Test func externalRecipientEditBumpsTheVersion() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        rig.backend.open[0].to.append("extra@example.invalid")
        #expect(await rig.drafts.refresh(d.id, present: false).draft?.version == 2)
    }

    @Test func closedDraftIsGone() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        rig.backend.open = []
        #expect(await rig.drafts.refresh(d.id, present: true).error == .draftGone)
    }

    @Test func twoMatchingDraftsAreNotGuessed() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        rig.backend.open.append(rig.backend.open[0])
        #expect(await rig.drafts.refresh(d.id, present: true).error == .draftAmbiguous(2))
    }

    @Test func hiddenDraftIsUnverifiedOnReview() async throws {
        let rig = DraftRig()
        let d = try #require(await rig.create().draft)
        rig.backend.open[0].visible = false
        #expect(await rig.drafts.refresh(d.id, present: true).status == .unverified)
    }
}
