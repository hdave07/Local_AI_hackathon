// Copied from the module's own test target (test targets cannot import each other).
import Foundation
@testable import FlowMail

/// Simulated Apple Mail. Tests can remove, replace or edit messages between search and
/// open to exercise revalidation, and control what is "visible" after opening.
@MainActor
final class FakeMailBackend: MailBackend {
    var availabilityValue: MailAvailability = .ready(accounts: 1)
    var messages: [MailMessageRef: (summary: MailMessageSummary, body: String)] = [:]
    var searchError: MailError?
    var frontWindowAfterOpen: ((MailMessageSummary) -> String?)? = { $0.subject + " — Inbox" }
    var markReadOnOpen = true
    private(set) var log: [String] = []
    private var nextID = 100

    @discardableResult
    func add(_ name: String, _ address: String, _ subject: String, body: String = "Hello there.\nSecond line.",
             mailbox: String = "INBOX", account: String? = "Work", daysAgo: Double = 0, read: Bool = false) -> MailMessageRef {
        nextID += 1
        let ref = MailMessageRef(messageID: "msg-\(nextID)@example.invalid", mailbox: MailboxRef(account: account, path: mailbox), internalID: nextID)
        let summary = MailMessageSummary(ref: ref, senderName: name, senderAddress: address, subject: subject,
                                         dateReceived: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400), isRead: read)
        messages[ref] = (summary, body)
        return ref
    }

    func edit(_ ref: MailMessageRef, subject: String? = nil, messageID: String? = nil) {
        guard let (s, body) = messages[ref] else { return }
        let newRef = MailMessageRef(messageID: messageID ?? s.ref.messageID, mailbox: s.ref.mailbox, internalID: s.ref.internalID)
        let new = MailMessageSummary(ref: newRef, senderName: s.senderName, senderAddress: s.senderAddress,
                                     subject: subject ?? s.subject, dateReceived: s.dateReceived, isRead: s.isRead)
        messages[ref] = (new, body)
    }

    // MARK: MailBackend

    func availability(requestPermission: Bool) async -> MailAvailability {
        log.append("availability(\(requestPermission))")
        return availabilityValue
    }

    func search(_ query: MailQuery) async throws(MailError) -> MailSearchResult {
        log.append("search")
        if let searchError { throw searchError }
        func has(_ s: String, _ q: String) -> Bool { s.range(of: q, options: [.caseInsensitive]) != nil }
        let hits = messages.values.map(\.summary).filter { m in
            if let mb = query.mailbox, !has(m.ref.mailbox.path, mb) { return false }
            if let s = query.sender, !has(m.sender, s) { return false }
            if let s = query.subject, !has(m.subject, s) { return false }
            return query.terms.allSatisfy { has(m.subject, $0) || has(m.sender, $0) }
        }.sorted { ($0.dateReceived ?? .distantPast) > ($1.dateReceived ?? .distantPast) }
        return MailSearchResult(messages: Array(hits.prefix(query.limit)), total: hits.count)
    }

    /// Like Mail: looks up by mailbox + internal id; the Message-ID found there may differ.
    func lookup(_ ref: MailMessageRef) async throws(MailError) -> MailMessageSummary {
        log.append("lookup \(ref.internalID)")
        guard let entry = messages.first(where: { $0.key.internalID == ref.internalID && $0.key.mailbox == ref.mailbox }) else {
            throw .messageGone
        }
        return entry.value.summary
    }

    func lookupWithContent(_ ref: MailMessageRef) async throws(MailError) -> (MailMessageSummary, String) {
        let summary = try await lookup(ref)
        return (summary, messages[summary.ref]?.body ?? "")
    }

    func open(_ ref: MailMessageRef, expectedSubject: String) async throws(MailError) -> MailOpenOutcome {
        log.append("open \(ref.internalID)")
        guard let (s, body) = messages[ref] else { throw .messageGone }
        if markReadOnOpen {
            messages[ref] = (MailMessageSummary(ref: s.ref, senderName: s.senderName, senderAddress: s.senderAddress,
                                                subject: s.subject, dateReceived: s.dateReceived, isRead: true), body)
        }
        return MailOpenOutcome(frontWindow: frontWindowAfterOpen?(s), isReadAfter: markReadOnOpen ? true : s.isRead)
    }

    func content(_ ref: MailMessageRef) async throws(MailError) -> String {
        log.append("content \(ref.internalID)")
        guard let entry = messages[ref] else { throw .messageGone }
        return entry.body
    }

    var opens: [String] { log.filter { $0.hasPrefix("open") } }
}

@MainActor
final class FakeDisplayVerifier: MailDisplayVerifying {
    var windowMatches = true
    var bodyVisible = true
    private(set) var calls = 0
    func observe(subject: String, bodySnippet: String?) async -> (windowMatches: Bool, bodyVisible: Bool) {
        calls += 1
        return (windowMatches, bodyVisible)
    }
}

@MainActor
func makeMail(_ backend: FakeMailBackend, verifier: MailDisplayVerifying? = FakeDisplayVerifier(),
              lifetime: Duration = .seconds(300)) -> MailController {
    var c = MailController.Configuration()
    c.verifyTimeout = .milliseconds(30)
    c.pollInterval = .milliseconds(5)
    c.candidatesLifetime = lifetime
    return MailController(backend: backend, verifier: verifier, configuration: c)
}

/// Two Sarahs, a budget mail and an unrelated one.
@MainActor
func sampleMailbox() -> (FakeMailBackend, chen: MailMessageRef, okafor: MailMessageRef, budget: MailMessageRef) {
    let b = FakeMailBackend()
    let chen = b.add("Sarah Chen", "sarah.chen@example.invalid", "Meeting tomorrow",
                     body: "Hi,\r\n\r\n\r\n\r\nCan we meet tomorrow at 3 pm?\u{FFFC}\r\n\r\nSarah  ", daysAgo: 1)
    let okafor = b.add("Sarah Okafor", "sarah.okafor@example.invalid", "Lunch on Friday?", daysAgo: 2, read: true)
    let budget = b.add("Priya Patel", "priya.patel@example.invalid", "Project budget review", daysAgo: 3)
    b.add("Diego Ramirez", "diego@example.invalid", "Quarterly report", daysAgo: 4)
    return (b, chen, okafor, budget)
}
