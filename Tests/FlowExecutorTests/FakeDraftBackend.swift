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

    /// Mail rewrites what it is given (e.g. trailing whitespace) in some versions; tests set this.
    var transformWrite: ((String) -> String)?
    /// The write is accepted but the window keeps showing the old text (AX lag / failure).
    var windowIgnoresWrites = false
    var writeError: MailError?

    func draftDetails(subject: String) async throws(MailError) -> [OpenDraftDetail] {
        open.filter { $0.subject == subject }.map { OpenDraftDetail(to: $0.to, cc: $0.cc, bcc: $0.bcc, content: $0.body) }
    }

    func setDraftContent(subject: String, to: [String], expected: String, new: String) async throws(MailError) -> DraftContentWrite {
        log.append("setContent")
        if let writeError { throw writeError }
        let mine = open.indices.filter { open[$0].subject == subject && open[$0].to == to && open[$0].cc.isEmpty && open[$0].bcc.isEmpty }
        if mine.isEmpty { return .notFound }
        let exact = mine.filter { open[$0].body == expected }
        if exact.isEmpty { return .changed }
        if exact.count > 1 { return .ambiguous(exact.count) }
        let written = transformWrite?(new) ?? new
        if windowIgnoresWrites { shownBody[exact[0]] = open[exact[0]].body }
        open[exact[0]].body = written
        return .written(content: written)
    }

    /// What the compose window shows when it differs from the scripting text (index → body).
    var shownBody: [Int: String] = [:]
}

@MainActor
final class FakeComposeInspector: MailComposeInspecting {
    let backend: FakeDraftBackend
    var extraToTokens: [String] = []
    /// Report window identities, as the real inspector does.
    var tokens = true
    /// Other windows with the same title that are not drafts Flow made (e.g. opened by hand).
    var extraWindows: [MailComposeView] = []
    init(backend: FakeDraftBackend) { self.backend = backend }

    func compose(titled subject: String) -> [MailComposeView] {
        backend.open.indices.filter { backend.open[$0].subject == subject && backend.open[$0].visible }.map { i in
            let o = backend.open[i]
            return MailComposeView(title: o.subject, to: o.to + extraToTokens, cc: o.cc, subject: o.subject,
                                   body: backend.shownBody[i] ?? o.body, windowToken: tokens ? 1000 + i : nil)
        } + extraWindows.filter { $0.title == subject }
    }
}

