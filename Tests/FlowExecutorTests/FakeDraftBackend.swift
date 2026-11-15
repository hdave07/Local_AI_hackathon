// Copied from FlowMailTests/MailDraftTests.swift (test targets cannot import each other).
import FlowAX
@testable import FlowMail
import Foundation

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

