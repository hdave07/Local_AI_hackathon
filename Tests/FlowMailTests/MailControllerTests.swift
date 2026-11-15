import FlowAX
@testable import FlowMail
import Foundation
import Testing

@MainActor
@Suite("MailController")
struct MailControllerTests {
    // MARK: Availability and configuration

    @Test(arguments: [
        (MailAvailability.notInstalled, NavigationStatus.unsupported, MailError.notInstalled as MailError?),
        (.noAccounts, .unsupported, .noAccounts),
        (.automationDenied, .failed, .automationDenied),
        (.automationNotDetermined, .failed, .automationNotDetermined),
    ])
    func unavailableMailBlocksSearch(availability: MailAvailability, status: NavigationStatus, error: MailError?) async {
        let (b, _, _, _) = sampleMailbox()
        b.availabilityValue = availability
        let r = await makeMail(b).perform(.find(MailQuery(sender: "sarah")))
        #expect(r.status == status)
        #expect(r.error == error)
        #expect(!b.log.contains("search"), "nothing is searched without consent and a configured account")
    }

    @Test func statusReportsReady() async {
        let (b, _, _, _) = sampleMailbox()
        let r = await makeMail(b).perform(.status(requestPermission: false))
        #expect(r.status == .completed)
        #expect(b.log == ["availability(false)"], "status never prompts unless asked")
    }

    // MARK: Search

    @Test func findBySender() async {
        let (b, _, _, budget) = sampleMailbox()
        let r = await makeMail(b).perform(.find(MailQuery(sender: "priya")))
        #expect(r.status == .completed)
        #expect(r.messages.map(\.ref) == [budget])
        #expect(b.opens.isEmpty, "find never opens")
    }

    @Test func findBySubjectAndTerms() async {
        let (b, chen, _, budget) = sampleMailbox()
        let mail = makeMail(b)
        #expect(await mail.perform(.find(MailQuery(subject: "BUDGET"))).messages.map(\.ref) == [budget])
        #expect(await mail.perform(.find(MailQuery(sender: "sarah", terms: ["meeting"]))).messages.map(\.ref) == [chen])
    }

    @Test func multipleMatchesAskWithoutOpening() async {
        let (b, chen, okafor, _) = sampleMailbox()
        let r = await makeMail(b).perform(.open(MailQuery(sender: "sarah")))
        #expect(r.status == .needsClarification)
        #expect(r.clarification?.options.map(\.ref) == [chen, okafor], "newest first")
        #expect(r.userMessage.contains("2 different senders"))
        #expect(r.userMessage.contains("Sarah Okafor <sarah.okafor@example.invalid>"))
        #expect(b.opens.isEmpty)
    }

    @Test func noResultsIsAClearAnswer() async {
        let (b, _, _, _) = sampleMailbox()
        let r = await makeMail(b).perform(.read(MailQuery(sender: "nobody")))
        #expect(r.status == .completed)
        #expect(r.messages.isEmpty)
        #expect(r.totalMatches == 0)
        #expect(r.userMessage == "No messages from “nobody” in Inbox.")
        #expect(b.opens.isEmpty)
    }

    @Test func invalidQueries() async {
        let (b, _, _, _) = sampleMailbox()
        let mail = makeMail(b)
        #expect(await mail.perform(.find(MailQuery())).error == .invalidQuery("Say who the message is from, its subject, or what it's about."))
        guard case .invalidQuery = await mail.perform(.find(MailQuery(sender: String(repeating: "x", count: 201)))).error else {
            Issue.record("expected invalidQuery"); return
        }
        #expect(!b.log.contains("search"))
    }

    @Test func backendErrorsAreTyped() async {
        let (b, _, _, _) = sampleMailbox()
        b.searchError = .timedOut
        let r = await makeMail(b).perform(.find(MailQuery(sender: "sarah")))
        #expect(r.error == .timedOut)
        #expect(r.retrySafe)
        b.searchError = .mailboxNotFound("Nope")
        #expect(await makeMail(b).perform(.find(MailQuery(sender: "x", mailbox: "Nope"))).userMessage == "There's no mailbox called “Nope”.")
    }

    // MARK: Open

    @Test func uniqueOpenIsVerifiedAndBound() async {
        let (b, _, _, budget) = sampleMailbox()
        let mail = makeMail(b)
        let r = await mail.perform(.open(MailQuery(sender: "priya")))
        #expect(r.status == .completed)
        #expect(b.opens == ["open \(budget.internalID)"])
        #expect(r.observation == MailDisplayObservation(scriptedWindowMatches: true, visibleWindowMatches: true, bodyVisible: true))
        #expect(mail.activeMessage?.ref == budget)
        #expect(r.evidence.contains { $0.contains("Mail marked it as read") }, "observed, not caused, by Flow")
    }

    @Test func alreadyReadMessageHasNoReadNote() async {
        let (b, _, _, _) = sampleMailbox()
        let r = await makeMail(b).perform(.open(MailQuery(sender: "okafor")))
        #expect(!r.evidence.contains { $0.contains("marked it as read") })
    }

    @Test func chooseOpensExactlyTheChosenMessage() async {
        let (b, _, okafor, _) = sampleMailbox()
        let mail = makeMail(b)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        let r = await mail.perform(.choose(2))
        #expect(r.status == .completed)
        #expect(b.opens == ["open \(okafor.internalID)"])
        #expect(await mail.perform(.choose(1)).error == .noActiveCandidates, "candidates are single-use")
    }

    @Test func chooseErrors() async {
        let (b, _, _, _) = sampleMailbox()
        let mail = makeMail(b)
        #expect(await mail.perform(.choose(1)).error == .noActiveCandidates)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        #expect(await mail.perform(.choose(9)).error == .numberOutOfRange(9, count: 2))
    }

    @Test func expiredCandidatesAreRefused() async {
        let (b, _, _, _) = sampleMailbox()
        let mail = makeMail(b, lifetime: .zero)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        try? await Task.sleep(for: .milliseconds(5))
        #expect(await mail.perform(.choose(1)).error == .noActiveCandidates)
        #expect(b.opens.isEmpty)
    }

    // MARK: Revalidation

    @Test func deletedOrMovedMessageIsNotOpened() async {
        let (b, _, okafor, _) = sampleMailbox()
        let mail = makeMail(b)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        b.messages[okafor] = nil
        let r = await mail.perform(.choose(2))
        #expect(r.error == .messageGone)
        #expect(b.opens.isEmpty)
    }

    @Test func differentMessageAtSameReferenceIsRefused() async {
        let (b, chen, _, _) = sampleMailbox()
        let mail = makeMail(b)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        b.edit(chen, messageID: "someone-else@example.invalid")
        guard case .referenceChanged = await mail.perform(.choose(1)).error else { Issue.record("expected referenceChanged"); return }
        #expect(b.opens.isEmpty)
    }

    @Test func changedSubjectIsRefused() async {
        let (b, chen, _, _) = sampleMailbox()
        let mail = makeMail(b)
        _ = await mail.perform(.find(MailQuery(sender: "sarah")))
        b.edit(chen, subject: "Totally different")
        guard case .referenceChanged = await mail.perform(.choose(1)).error else { Issue.record("expected referenceChanged"); return }
        #expect(b.opens.isEmpty)
    }

    @Test func plannerRefIsRevalidated() async {
        let (b, chen, _, _) = sampleMailbox()
        let mail = makeMail(b)
        #expect(await mail.perform(.openMessage(chen)).status == .completed)
        let stale = MailMessageRef(messageID: "old@example.invalid", mailbox: chen.mailbox, internalID: chen.internalID)
        guard case .referenceChanged = await mail.perform(.openMessage(stale)).error else { Issue.record("expected referenceChanged"); return }
        let gone = MailMessageRef(messageID: chen.messageID, mailbox: chen.mailbox, internalID: 9_999)
        #expect(await mail.perform(.readMessage(gone)).error == .messageGone)
    }

    // MARK: Verification

    @Test func notVisibleOnScreenIsUnverified() async {
        let (b, _, _, _) = sampleMailbox()
        let verifier = FakeDisplayVerifier()
        verifier.windowMatches = false
        verifier.bodyVisible = false
        let mail = makeMail(b, verifier: verifier)
        let r = await mail.perform(.open(MailQuery(sender: "priya")))
        #expect(r.status == .unverified)
        #expect(mail.activeMessage != nil)
    }

    @Test func nothingObservedIsFailed() async {
        let (b, _, _, _) = sampleMailbox()
        b.frontWindowAfterOpen = { _ in "Inbox" }
        let verifier = FakeDisplayVerifier()
        verifier.windowMatches = false
        verifier.bodyVisible = false
        let mail = makeMail(b, verifier: verifier)
        let r = await mail.perform(.open(MailQuery(sender: "priya")))
        #expect(r.status == .failed)
        #expect(mail.activeMessage == nil)
    }

    @Test func withoutAccessibilityVerifierOpenIsUnverified() async {
        let (b, _, _, _) = sampleMailbox()
        #expect(await makeMail(b, verifier: nil).perform(.open(MailQuery(sender: "priya"))).status == .unverified)
    }

    // MARK: Read

    @Test func readReturnsCleanBody() async throws {
        let (b, _, _, _) = sampleMailbox()
        let r = await makeMail(b).perform(.read(MailQuery(sender: "chen")))
        #expect(r.status == .completed)
        let content = try #require(r.content)
        #expect(content.body == "Hi,\n\nCan we meet tomorrow at 3 pm?\n\nSarah")
        #expect(!content.truncated)
        #expect(!r.report.contains("Can we meet"), "reports never include the body")
    }

    @Test func emptyBodyIsUnsupported() async {
        let b = FakeMailBackend()
        b.add("Img Only", "img@example.invalid", "Picture", body: "\u{FFFC}\n \n")
        let r = await makeMail(b).perform(.read(MailQuery(sender: "img")))
        #expect(r.status == .unsupported)
        #expect(r.error == .contentUnavailable)
    }

    @Test func readActiveDoesNotReopen() async {
        let (b, _, _, budget) = sampleMailbox()
        let mail = makeMail(b)
        #expect(await mail.perform(.readActive).error == .noActiveMessage)
        _ = await mail.perform(.open(MailQuery(sender: "priya")))
        let r = await mail.perform(.readActive)
        #expect(r.status == .completed)
        #expect(r.content?.body == "Hello there.\nSecond line.")
        #expect(b.opens == ["open \(budget.internalID)"], "opened once only")
        b.messages[budget] = nil
        #expect(await mail.perform(.readActive).error == .messageGone)
    }
}
