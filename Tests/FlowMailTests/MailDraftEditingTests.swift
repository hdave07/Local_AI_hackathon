import FlowAX
@testable import FlowMail
import FlowText
import Foundation
import Testing

/// T-023B over **simulated** Mail: same-title compose windows, compare-and-set editing,
/// external changes, and on-screen verification. Nothing touches macOS.
@MainActor
@Suite("Compose window selection (duplicate titles)")
struct ComposeSelectionTests {
    static let subject = "Re: [FlowTest] Meeting tomorrow"
    static func view(_ to: [String], _ body: String, cc: [String] = [], token: Int? = nil) -> MailComposeView {
        MailComposeView(title: subject, to: to, cc: cc, subject: subject, body: body, windowToken: token)
    }
    let names = ["Sarah Chen", "sarah.chen@example.invalid"]

    @Test func titleAloneNeverSelects() {
        let other = Self.view(["Priya Patel"], "FLOWTEST SAFE: I can meet at 3")
        #expect(MailDraftController.select([other], token: nil, names: names, require: "FLOWTEST SAFE: I can meet at 3") == .none)
    }

    @Test func recipientsAndBodyPickTheOneMatch() {
        let mine = Self.view(["Sarah Chen"], "FLOWTEST SAFE: I can meet at 3")
        let views = [Self.view(["Priya Patel"], "FLOWTEST SAFE: I can meet at 3"), Self.view(["Sarah Chen"], "something else"),
                     Self.view(["Sarah Chen"], "FLOWTEST SAFE: I can meet at 3", cc: ["team@example.invalid"]), mine]
        #expect(MailDraftController.select(views, token: nil, names: names, require: "FLOWTEST SAFE: I can meet at 3") == .one(mine))
    }

    @Test func equalMatchesAreAmbiguous() {
        let a = Self.view(["Sarah Chen"], "FLOWTEST SAFE: I can meet at 3")
        #expect(MailDraftController.select([a, a], token: nil, names: names, require: "FLOWTEST SAFE: I can meet at 3") == .ambiguous(2))
        #expect(MailDraftController.select([a, a], token: nil, names: names) == .ambiguous(2))
    }

    @Test func windowIdentityDecides() {
        let a = Self.view(["Sarah Chen"], "same", token: 1), b = Self.view(["Sarah Chen"], "same", token: 2)
        #expect(MailDraftController.select([a, b], token: 2, names: names) == .one(b))
        // Identity holds even after the user edited recipients by hand (reported as a change).
        let edited = Self.view(["Sarah Chen", "Boss"], "same", token: 2)
        #expect(MailDraftController.select([a, edited], token: 2, names: names) == .one(edited))
    }

    @Test func lastVerifiedBodyBreaksATie() {
        let a = Self.view(["Sarah Chen"], "I can meet at 3"), b = Self.view(["Sarah Chen"], "I can meet at 3, see you")
        #expect(MailDraftController.select([a, b], token: nil, names: names, prefer: "I can meet at 3, see you") == .one(b))
    }
}

@MainActor
@Suite("MailDraftController: duplicate windows in creation and review")
struct DuplicateWindowTests {
    @Test func creationIgnoresASameTitledWindowForSomeoneElse() async throws {
        let rig = DraftRig()
        rig.inspector.extraWindows = [ComposeSelectionTests.view(["Priya Patel"], "unrelated", token: 7)]
        let r = await rig.create()
        #expect(r.status == .completed)
        #expect(r.evidence.contains { $0.contains("exactly one has these recipients and this text") })
    }

    @Test func creationWithTwoEquallyMatchingWindowsIsAnAmbiguityError() async {
        let rig = DraftRig()
        rig.inspector.extraWindows = [ComposeSelectionTests.view(["Sarah Chen"], "FLOWTEST SAFE: I can meet at 3", token: 7)]
        let r = await rig.create()
        #expect(r.status == .failed)
        #expect(r.error == .draftAmbiguous(2))
        #expect(r.draft == nil, "not reported as Flow's draft")
        let retry = await rig.create()
        #expect(rig.backend.creates == 1, "a retry of the same step never creates another draft")
        #expect(retry.status != .completed)
    }

    @Test func reviewIgnoresAnotherWindowWithTheSameTitle() async throws {
        let rig = DraftRig()
        let id = try #require(await rig.create().draft?.id)
        rig.inspector.extraWindows = [ComposeSelectionTests.view(["Sarah Chen"], "a different reply", token: 7)]
        let r = await rig.drafts.refresh(id, present: false)
        #expect(r.status == .completed)
        #expect(r.draft?.body == "FLOWTEST SAFE: I can meet at 3")
        #expect(r.draft?.version == 1, "the other window's text is not taken as an edit")
    }

    @Test func reviewWithoutIdentityAndEqualWindowsIsAmbiguous() async throws {
        let rig = DraftRig()
        rig.inspector.tokens = false
        let id = try #require(await rig.create().draft?.id)
        rig.inspector.extraWindows = [ComposeSelectionTests.view(["Sarah Chen"], "FLOWTEST SAFE: I can meet at 3")]
        let r = await rig.drafts.refresh(id, present: false)
        #expect(r.error == .draftAmbiguous(2))
    }
}

@MainActor
@Suite("MailDraftController: editing (compare-and-set)")
struct MailDraftEditingTests {
    func created(_ rig: DraftRig) async throws -> String {
        try #require(await rig.create("FLOWTEST SAFE: I can meet at 3:30").draft?.id)
    }

    @Test func readsTheAuthoredTextExactly() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        let t = try #require(await rig.drafts.editableText(id).text)
        #expect(t.authored == "FLOWTEST SAFE: I can meet at 3:30")
        #expect(t.quoted.isEmpty)
        #expect(t.version == 1)
    }

    @Test func replaceWritesVerifiesAndBumpsTheVersion() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30",
                                                 newText: "FLOWTEST SAFE: I can meet at 4")
        #expect(r.status == .completed)
        #expect(r.draft?.version == 2)
        #expect(r.draft?.body == "FLOWTEST SAFE: I can meet at 4")
        #expect(rig.backend.open.count == 1 && rig.backend.creates == 1, "edited in place, no new draft")
        #expect(rig.backend.open[0].to == ["sarah.chen@example.invalid"] && rig.backend.open[0].cc.isEmpty)
        #expect(rig.backend.open[0].subject == "Re: [FlowTest] Meeting tomorrow")
    }

    @Test func quotedOriginalIsKeptByteForByte() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        let quote = "\n\nOn 13 Nov 2026, at 09:14, Sarah Chen <sarah.chen@example.invalid> wrote:\n\n> Can we meet tomorrow?\n> \u{00A0}Thanks"
        rig.backend.open[0].body += quote
        let t = try #require(await rig.drafts.editableText(id).text)
        #expect(t.authored == "FLOWTEST SAFE: I can meet at 3:30")
        #expect(t.quoted == quote)
        let r = await rig.drafts.replaceAuthored(id, baseVersion: t.version, baseText: t.authored, newText: "FLOWTEST SAFE: 4 works")
        #expect(r.status == .completed)
        #expect(rig.backend.open[0].body == "FLOWTEST SAFE: 4 works" + quote)
    }

    @Test func externalChangeBumpsTheVersionAndStaleWritesAreRefused() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        let before = try #require(await rig.drafts.editableText(id).text)
        rig.backend.open[0].body = "FLOWTEST SAFE: I can meet at 3:30, typed by me"
        let after = try #require(await rig.drafts.editableText(id).text)
        #expect(after.version > before.version)
        let r = await rig.drafts.replaceAuthored(id, baseVersion: before.version, baseText: before.authored, newText: "overwrite")
        #expect(r.error == .draftChanged)
        #expect(rig.backend.open[0].body == "FLOWTEST SAFE: I can meet at 3:30, typed by me", "the user's text is intact")
        #expect(!rig.backend.log.contains("setContent"))
    }

    @Test func aWriteNotShownOnScreenIsUnverified() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        rig.backend.windowIgnoresWrites = true
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30", newText: "FLOWTEST SAFE: 4")
        #expect(r.status == .unverified)
    }

    @Test func withoutAccessibilityAWriteIsUnverified() async throws {
        let rig = DraftRig(withInspector: false)
        let id = try #require(await rig.create("FLOWTEST SAFE: I can meet at 3:30").draft?.id)
        let t = try #require(await rig.drafts.editableText(id).text)
        let r = await rig.drafts.replaceAuthored(id, baseVersion: t.version, baseText: t.authored, newText: "FLOWTEST SAFE: 4")
        #expect(r.status == .unverified, "an open compose window is not proof; the new text must be seen")
    }

    @Test func mailRewritingTheTextIsNotReportedAsDone() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        rig.backend.transformWrite = { $0 + " (autocorrected)" }
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30", newText: "FLOWTEST SAFE: 4")
        #expect(r.status == .unverified)
        #expect(r.evidence.contains { $0.contains("exactly the new text, quote preserved: false") })
    }

    @Test func timeoutIsUnverifiedAndTheNextReadReportsTheTruth() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        rig.backend.writeError = .timedOut
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30", newText: "x")
        #expect(r.status == .unverified)
        #expect(await rig.drafts.editableText(id).text?.authored == "FLOWTEST SAFE: I can meet at 3:30")
    }

    @Test func twoIdenticalDraftsAreNeverEditedByGuess() async throws {
        let rig = DraftRig()
        rig.inspector.tokens = false
        let id = try await created(rig)
        rig.backend.open.append(.init(subject: "Re: [FlowTest] Meeting tomorrow", to: ["sarah.chen@example.invalid"],
                                      body: "FLOWTEST SAFE: I can meet at 3:30"))
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30", newText: "x")
        #expect(r.status == .failed)
        #expect(rig.backend.open.allSatisfy { $0.body == "FLOWTEST SAFE: I can meet at 3:30" })
    }

    @Test func aDraftThatIsGoneIsReportedNotRecreated() async throws {
        let rig = DraftRig()
        let id = try await created(rig)
        rig.backend.open.removeAll()  // the user closed it
        let r = await rig.drafts.replaceAuthored(id, baseVersion: 1, baseText: "FLOWTEST SAFE: I can meet at 3:30", newText: "x")
        #expect(r.error == .draftGone)
        #expect(rig.backend.creates == 1)
    }
}

@Suite("Authored text split")
struct AuthoredTextTests {
    @Test(arguments: [
        ("Hi\n\nOn Fri, Sarah wrote:\n> hello", "Hi", "\n\nOn Fri, Sarah wrote:\n> hello"),
        ("Hi\n-----Original Message-----\nFrom: x", "Hi", "\n-----Original Message-----\nFrom: x"),
        ("Hi\n> quoted", "Hi", "\n> quoted"),
        ("No quote here. On Monday it rained.", "No quote here. On Monday it rained.", ""),
    ])
    func splits(body: String, authored: String, quoted: String) {
        let s = AuthoredText.split(body)
        #expect(s.authored == authored)
        #expect(s.quoted == quoted)
        #expect(s.authored + s.quoted == body)
    }
}
