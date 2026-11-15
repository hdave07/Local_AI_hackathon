import ApplicationServices
import AppKit
import FlowAX
import FlowText
import Foundation

// MARK: - Types

/// A Flow-created reply draft as last verified in Mail's real compose window.
public struct MailDraftState: Sendable, Equatable {
    /// Flow's identity for the draft (Mail gives unsent messages no usable id).
    public let id: String
    /// Recipient addresses from Mail's scripting interface.
    public let recipients: [String]
    /// Recipient tokens as shown in the compose window's To field.
    public let visibleRecipients: [String]
    public let subject: String
    /// The body text visible in the compose window.
    public let body: String
    /// Increases whenever the live draft differs from the last verified state.
    public let version: Int
    /// The message this draft replies to.
    public let inReplyTo: MailMessageRef
}

/// What Mail's scripting interface reported when asked to create a reply.
public enum ReplyCreation: Sendable, Equatable {
    /// A reply was created hidden, checked, filled and shown.
    case created(subject: String, to: [String], cc: [String], bcc: [String], contentSet: Bool, windowShown: Bool)
    /// Replies to this message are already open; nothing was created.
    case existing(subject: String, drafts: [OpenDraftInfo])
    /// Mail would address the reply differently; the hidden draft was discarded unseen.
    case mismatch(to: [String], cc: [String], bcc: [String])
}

public struct OpenDraftInfo: Sendable, Equatable {
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]

    public init(to: [String], cc: [String], bcc: [String]) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
    }
}

/// The compose window as seen through Accessibility.
public struct MailComposeView: Sendable, Equatable {
    public let title: String
    public let to: [String]
    public let cc: [String]
    public let subject: String
    public let body: String
    /// Identity of the window element (`CFHash` of its `AXUIElement`), stable while the
    /// window is open. Same-titled windows are told apart by it, never by title.
    public let windowToken: Int?

    public init(title: String, to: [String], cc: [String], subject: String, body: String, windowToken: Int? = nil) {
        self.title = title
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.windowToken = windowToken
    }
}

/// An open draft as Mail's scripting interface reports it, including its exact text.
public struct OpenDraftDetail: Sendable, Equatable {
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]
    /// The draft's full plain text (`content` of the outgoing message), exactly.
    public let content: String

    public init(to: [String], cc: [String], bcc: [String], content: String) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.content = content
    }
}

/// Outcome of a compare-and-set write of a draft's text.
public enum DraftContentWrite: Sendable, Equatable {
    /// Exactly one draft matched subject, recipients and the expected text; this is its text now.
    case written(content: String)
    /// A draft with that subject and those recipients exists, but its text is not the expected
    /// text (changed outside Flow). Nothing was written.
    case changed
    case notFound
    /// Several drafts match equally; nothing was written.
    case ambiguous(Int)
}

/// Mail scripting operations for drafts. There is no send, save or delete operation.
@MainActor
public protocol MailDraftBackend: AnyObject {
    /// Atomically: revalidate, refuse if a reply is already open, create the reply hidden
    /// (reply-all off), check its recipients, fill the text, then show it.
    func createReplyDraft(_ ref: MailMessageRef, recipient: String, content: String) async throws(MailError) -> ReplyCreation
    /// Open (unsent) drafts with this subject.
    func openDrafts(subject: String) async throws(MailError) -> [OpenDraftInfo]
    /// Brings the single open draft with this subject to the front. Returns how many matched.
    func showDraft(subject: String) async throws(MailError) -> Int
    /// Open drafts with this subject, with their exact text (T-023B).
    func draftDetails(subject: String) async throws(MailError) -> [OpenDraftDetail]
    /// Compare-and-set (T-023B): replaces the text of the one open draft with this subject and
    /// exactly these To recipients (no Cc/Bcc) **only if** its text is still `expected`. Never
    /// changes recipients or subject; never sends, saves or closes the draft.
    func setDraftContent(subject: String, to: [String], expected: String, new: String) async throws(MailError) -> DraftContentWrite
}

@MainActor
public protocol MailComposeInspecting: AnyObject {
    /// Reads every visible compose window titled `subject` (0, 1 or more).
    func compose(titled subject: String) -> [MailComposeView]
}

// MARK: - Compose parsing (pure, unit-tested)

/// A minimal Accessibility node, so compose parsing can be tested without Mail.
public struct ComposeNode: Sendable, Equatable {
    public var role: String
    public var subrole: String?
    public var identifier: String?
    public var description: String?
    public var value: String?
    public var children: [ComposeNode]

    public init(role: String, subrole: String? = nil, identifier: String? = nil, description: String? = nil,
                value: String? = nil, children: [ComposeNode] = []) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.description = description
        self.value = value
        self.children = children
    }
}

public enum ComposeParser {
    /// Reads To/Cc tokens, subject and body text from a compose window tree (Mail 16 layout:
    /// `Mail.toField` / `Mail.ccField` with `AXTextAttachment` tokens, `Mail.subjectField`, and a
    /// web area described "message body").
    public static func parse(title: String, window: ComposeNode) -> MailComposeView {
        func find(_ n: ComposeNode, _ p: (ComposeNode) -> Bool) -> ComposeNode? {
            if p(n) { return n }
            for c in n.children { if let f = find(c, p) { return f } }
            return nil
        }
        func tokens(_ id: String) -> [String] {
            guard let field = find(window, { $0.identifier == id }) else { return [] }
            let attachments = field.children.filter { $0.subrole == "AXTextAttachment" }.compactMap(\.value)
                .map(clean).filter { !$0.isEmpty }
            if !attachments.isEmpty { return attachments }
            let typed = clean(field.value ?? "")
            return typed.isEmpty ? [] : typed.split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
        }
        let subject = clean(find(window, { $0.identifier == "Mail.subjectField" })?.value ?? "")
        var lines: [String] = []
        if let body = find(window, { $0.role == "AXWebArea" && ($0.description ?? "").lowercased().contains("message body") }) {
            func collect(_ n: ComposeNode) {
                if n.role == "AXStaticText", let v = n.value { lines.append(v) }
                n.children.forEach(collect)
            }
            collect(body)
        }
        return MailComposeView(title: title, to: tokens("Mail.toField"), cc: tokens("Mail.ccField"), subject: subject,
                               body: normalize(lines.joined(separator: "\n")))
    }

    /// Whitespace-normalized text for comparisons (NBSP, attachment marks, runs of spaces).
    public static func normalize(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{FFFC}", with: "")
        let lines = cleaned.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
        var out: [String] = []
        for line in lines where !(line.isEmpty && (out.last?.isEmpty ?? true)) { out.append(line) }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clean(_ s: String) -> String {
        LabelText.clean(s.replacingOccurrences(of: "\u{FFFC}", with: ""))
    }
}

// MARK: - Real Accessibility reader

/// Reads Mail's compose windows through the public Accessibility API. Booleans and text
/// stay in memory; nothing is logged.
@MainActor
public final class AXMailComposeInspector: MailComposeInspecting {
    public init() {}

    public func compose(titled subject: String) -> [MailComposeView] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: JXAMailBackend.bundleID).first else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1.0)
        let windows = (Self.attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.compactMap { w in
            guard let title = Self.attr(w, kAXTitleAttribute) as? String, title == subject else { return nil }
            let v = ComposeParser.parse(title: title, window: Self.node(w, depth: 0))
            return MailComposeView(title: v.title, to: v.to, cc: v.cc, subject: v.subject, body: v.body, windowToken: Int(bitPattern: UInt(CFHash(w))))
        }
    }

    static func node(_ e: AXUIElement, depth: Int) -> ComposeNode {
        let children = depth < 18 ? ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).map { node($0, depth: depth + 1) } : []
        return ComposeNode(role: attr(e, kAXRoleAttribute) as? String ?? "?", subrole: attr(e, kAXSubroleAttribute) as? String,
                           identifier: attr(e, kAXIdentifierAttribute) as? String,
                           description: attr(e, kAXDescriptionAttribute) as? String, value: attr(e, kAXValueAttribute) as? String,
                           children: children)
    }

    static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }
}

// MARK: - Controller

/// The editable part of a draft: what the user wrote, above the quoted original.
public struct MailDraftText: Sendable, Equatable {
    public let draftID: String
    public let authored: String
    /// The quoted original (with its separator), preserved by every edit.
    public let quoted: String
    public let version: Int
}

public struct MailDraftTextResult: Sendable, Equatable {
    public let text: MailDraftText?
    public let error: MailError?
    public let evidence: [String]
    public let userMessage: String
}

public struct MailDraftEditResult: Sendable, Equatable {
    public let status: NavigationStatus
    public let draft: MailDraftState?
    /// The authored text read back after the write (nil if unknown).
    public let authored: String?
    public let error: MailError?
    public let evidence: [String]
    public let userMessage: String
}

public struct MailDraftResult: Sendable, Equatable {
    public let status: NavigationStatus
    public let draft: MailDraftState?
    public let error: MailError?
    public let evidence: [String]
    public let userMessage: String
}

/// Creates and presents reply drafts for verified messages (T-023A). Never sends, saves,
/// discards or deletes a draft the user can see.
///
/// - The original message is revalidated (same Message-ID, subject, sender) before replying.
/// - Mail creates the reply with reply-all off; its recipients must be exactly the original
///   sender with no Cc/Bcc, or the unseen draft is discarded and the mismatch reported.
/// - The draft counts as created only when Accessibility shows one compose window with that
///   subject, a single To token, no Cc, and the requested text in the body.
/// - Each plan step creates at most one draft (`key`), and an already-open reply to the same
///   message is reused (same text) or refused (different text): uncertain outcomes never
///   produce duplicates.
/// - Every later read re-checks the live window; any difference from the last verified state
///   bumps the version, so stale snapshots and approvals no longer match.
@MainActor
public final class MailDraftController {
    public struct Configuration: Sendable {
        public var verifyTimeout: Duration = .seconds(4)
        public var pollInterval: Duration = .milliseconds(150)
        public init() {}
    }

    struct Entry {
        var state: MailDraftState
        let senderName: String
        /// The compose window this draft was verified in (same-title windows are not it).
        var windowToken: Int?
        /// The exact text last read or written through scripting (edits compare against it).
        var content: String?
    }

    let mail: MailBackend
    let backend: MailDraftBackend
    let inspector: MailComposeInspecting?
    let configuration: Configuration
    private(set) var entries: [String: Entry] = [:]
    private var byKey: [String: String] = [:]

    public init(mail: MailBackend, backend: MailDraftBackend, inspector: MailComposeInspecting?,
                configuration: Configuration = Configuration()) {
        self.mail = mail
        self.backend = backend
        self.inspector = inspector
        self.configuration = configuration
    }

    public func state(_ id: String) -> MailDraftState? { entries[id]?.state }

    // MARK: Create

    public func createReply(to ref: MailMessageRef, expected: MailMessageSummary? = nil, content: String, key: String)
        async -> MailDraftResult
    {
        // At most one draft per plan step: a repeated request reports the draft it made.
        if let id = byKey[key], entries[id] != nil {
            return await refresh(id, present: false, evidence: ["this step already created draft \(id); not duplicated"])
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return failure(.emptyContent) }

        let original: MailMessageSummary
        do throws(MailError) {
            original = try await mail.lookup(ref)
            try MailController.check(original, ref: ref, expected: expected)
        } catch {
            return failure(error)
        }
        guard !original.senderAddress.isEmpty else { return failure(.noReplyAddress) }
        if Task.isCancelled { return MailDraftResult(status: .failed, draft: nil, error: nil, evidence: [], userMessage: "Cancelled before creating the reply.") }

        let sender = original.senderAddress.lowercased()
        let creation: ReplyCreation
        do throws(MailError) {
            creation = try await backend.createReplyDraft(original.ref, recipient: sender, content: text)
        } catch {
            // Unknown outcome (e.g. timeout): a draft may exist. A retry goes through the
            // "already open" check below instead of creating another.
            return MailDraftResult(status: error == .timedOut ? .unverified : .failed, draft: nil, error: error,
                                   evidence: ["create reply: \(error)"], userMessage: error == .timedOut
                                       ? "Mail didn't answer in time; a reply may be open. I won't create another automatically."
                                       : error.userMessage)
        }

        switch creation {
        case .mismatch(let to, let cc, let bcc):
            return failure(.recipientMismatch(expected: sender, actual: to + cc + bcc),
                           evidence: ["Mail's reply would go to \(to + cc + bcc); discarded before it was shown"])

        case .existing(let subject, let drafts):
            guard drafts.count == 1, drafts[0].to == [sender], drafts[0].cc.isEmpty, drafts[0].bcc.isEmpty,
                  let view = await waitForCompose(subject, expecting: text, senderName: original.senderName, sender: sender).view,
                  ComposeParser.normalize(view.body).contains(ComposeParser.normalize(text))
            else {
                return failure(.draftAlreadyOpen, evidence: ["\(drafts.count) open repl\(drafts.count == 1 ? "y" : "ies") to this message"])
            }
            let state = register(key: key, subject: subject, to: [sender], view: view, ref: original.ref, senderName: original.senderName)
            return MailDraftResult(status: .completed, draft: state, error: nil,
                                   evidence: ["a matching reply was already open; reused it instead of creating a duplicate"],
                                   userMessage: "That reply is already open in Mail.")

        case .created(let subject, let to, let cc, let bcc, let contentSet, let windowShown):
            let check = await waitForCompose(subject, expecting: text, senderName: original.senderName, sender: sender)
            if let n = check.ambiguous {
                // Registered (so this step never creates another), but not reported as Flow's draft.
                _ = register(key: key, subject: subject, to: to, view: nil, ref: original.ref, senderName: original.senderName,
                             fallbackBody: text)
                return failure(.draftAmbiguous(n), evidence: ["Mail reply (reply-all off): To \(to), Cc \(cc), Bcc \(bcc)"] + check.notes)
            }
            let state = register(key: key, subject: subject, to: to, view: check.view, ref: original.ref,
                                 senderName: original.senderName, fallbackBody: text)
            var evidence = ["revalidated original (same Message-ID, subject, sender)",
                            "Mail reply (reply-all off): To \(to), Cc \(cc), Bcc \(bcc)",
                            "text set via scripting: \(contentSet); window shown: \(windowShown)"]
            evidence += check.notes
            let verified = contentSet && check.ok
            return MailDraftResult(status: verified ? .completed : .unverified, draft: state, error: nil, evidence: evidence,
                                   userMessage: verified
                                       ? "Reply to \(original.senderName.isEmpty ? sender : original.senderName) is open in Mail, not sent."
                                       : "Mail opened a reply, but I couldn't confirm its contents on screen. Check it before doing anything else.")
        }
    }

    // MARK: Review / live state

    /// Re-reads the live draft; with `present`, brings its window forward and verifies it is shown.
    public func refresh(_ id: String, present: Bool, evidence prior: [String] = []) async -> MailDraftResult {
        guard var entry = entries[id] else { return failure(.unknownDraft) }
        let subject = entry.state.subject
        let open: [OpenDraftInfo]
        do throws(MailError) {
            open = try await backend.openDrafts(subject: subject)
        } catch {
            return failure(error)
        }
        guard !open.isEmpty else { entries[id] = nil; return failure(.draftGone) }
        // Same subject is not the same draft: several open drafts must be told apart by
        // recipients, then by their exact text. Equal candidates are ambiguous, never "the first".
        var mine = open.count == 1 ? open : open.filter { $0.to + $0.cc + $0.bcc == entry.state.recipients }
        if mine.count > 1 {
            switch await liveDetail(entry) {
            case .success(let d): mine = [OpenDraftInfo(to: d.to, cc: d.cc, bcc: d.bcc)]
            case .failure(let e): return failure(e == .draftChanged ? .draftAmbiguous(mine.count) : e)
            }
        }
        guard mine.count == 1 else { return failure(.draftAmbiguous(open.count)) }
        if present {
            do throws(MailError) {
                let shown = try await backend.showDraft(subject: subject)
                guard shown == 1 else { return failure(shown == 0 ? .draftGone : .draftAmbiguous(shown)) }
            } catch {
                return failure(error)
            }
        }
        let views = await waitForVisible(subject)
        var evidence = prior
        let view: MailComposeView?
        switch Self.select(views, token: entry.windowToken, names: [entry.senderName] + entry.state.recipients, prefer: entry.state.body) {
        case .one(let v):
            view = v
            if views.count > 1 { evidence.append("\(views.count) windows titled “\(subject)”; identified Flow's by window identity, recipients and text") }
        case .ambiguous(let n):
            return failure(.draftAmbiguous(n), evidence: ["\(n) compose windows titled “\(subject)” match equally; not guessing"])
        case .none:
            if views.isEmpty {
                view = nil
            } else if views.count == 1, entry.windowToken == nil {
                view = views[0]  // the only window with this title, changed (e.g. recipients edited by hand)
            } else if entry.windowToken != nil {
                view = nil
                evidence.append("Flow's compose window isn't open; \(views.count) other window(s) share its title and were not used")
            } else {
                return failure(.draftAmbiguous(views.count), evidence: ["\(views.count) compose windows titled “\(subject)”; none is clearly Flow's"])
            }
        }
        if entry.windowToken == nil, let token = view?.windowToken { entry.windowToken = token; entries[id] = entry }
        let liveBody = view.map(\.body) ?? entry.state.body
        let live = (recipients: mine[0].to + mine[0].cc + mine[0].bcc, body: ComposeParser.normalize(liveBody))
        let changed = live.recipients != entry.state.recipients || live.body != ComposeParser.normalize(entry.state.body)
            || (view.map { !entry.state.visibleRecipients.isEmpty && $0.to != entry.state.visibleRecipients } ?? false)
        if changed {
            entry.state = MailDraftState(id: id, recipients: live.recipients, visibleRecipients: view?.to ?? entry.state.visibleRecipients,
                                         subject: subject, body: live.body, version: entry.state.version + 1,
                                         inReplyTo: entry.state.inReplyTo)
            entries[id] = entry
            evidence.append("the draft changed outside Flow; now version \(entry.state.version)")
        }
        evidence.append("live draft: To \(live.recipients), body \(live.body.count) characters\(view == nil ? " (window not visible)" : "")")
        let status: NavigationStatus = present && view == nil ? .unverified : .completed
        let message: String
        if status == .unverified {
            message = "I couldn't confirm the draft is showing."
        } else if changed {
            message = "The draft was changed outside Flow; this is its current version."
        } else {
            message = present ? "Here's the unsent draft." : "The draft is unchanged."
        }
        return MailDraftResult(status: status, draft: entry.state, error: nil, evidence: evidence, userMessage: message)
    }

    // MARK: Editing (T-023B)

    /// The draft's authored text (what the user wrote, above any quoted original), read
    /// exactly through scripting, with the draft's current version. Any change since Flow
    /// last read or wrote it, by anyone, bumps the version first.
    public func editableText(_ id: String) async -> MailDraftTextResult {
        let checked = await refresh(id, present: false)
        guard checked.status == .completed, let state = checked.draft, var entry = entries[id] else {
            return .init(text: nil, error: checked.error ?? .draftGone, evidence: checked.evidence, userMessage: checked.userMessage)
        }
        let detail: OpenDraftDetail
        switch await liveDetail(entry) {
        case .success(let d): detail = d
        case .failure(let e): return .init(text: nil, error: e, evidence: checked.evidence, userMessage: e.userMessage)
        }
        var evidence = checked.evidence
        if let known = entry.content, known != detail.content {
            entry.state = MailDraftState(id: id, recipients: state.recipients, visibleRecipients: state.visibleRecipients, subject: state.subject,
                                         body: state.body, version: state.version + 1, inReplyTo: state.inReplyTo)
            evidence.append("draft text changed outside Flow; now version \(entry.state.version)")
        }
        entry.content = detail.content
        entries[id] = entry
        let parts = AuthoredText.split(detail.content)
        return .init(text: MailDraftText(draftID: id, authored: parts.authored, quoted: parts.quoted, version: entry.state.version),
                     error: nil, evidence: evidence, userMessage: "")
    }

    /// Replaces the authored text, only if the draft is still exactly `baseVersion` with
    /// authored text `baseText`. The quoted original is kept byte for byte; recipients and
    /// subject are never written. Success needs scripting to return the new text *and* the
    /// draft's compose window (same identity, same recipients, no Cc) to show it.
    public func replaceAuthored(_ id: String, baseVersion: Int, baseText: String, newText: String) async -> MailDraftEditResult {
        let current = await editableText(id)
        guard let base = current.text, var entry = entries[id] else {
            return .init(status: .failed, draft: nil, authored: nil, error: current.error ?? .draftGone, evidence: current.evidence,
                         userMessage: current.userMessage)
        }
        guard base.version == baseVersion, base.authored == baseText else {
            return .init(status: .failed, draft: entry.state, authored: base.authored, error: .draftChanged, evidence: current.evidence,
                         userMessage: MailError.draftChanged.userMessage)
        }
        if Task.isCancelled {
            return .init(status: .failed, draft: entry.state, authored: base.authored, error: nil, evidence: current.evidence,
                         userMessage: "Stopped before changing the draft.")
        }
        let expected = base.authored + base.quoted
        let desired = newText + base.quoted
        var evidence = current.evidence
        let write: DraftContentWrite
        do throws(MailError) {
            write = try await backend.setDraftContent(subject: entry.state.subject, to: entry.state.recipients,
                                                      expected: expected, new: desired)
        } catch {
            // Unknown outcome: the next read compares the live text and reports what happened.
            entry.content = nil
            entries[id] = entry
            return .init(status: error == .timedOut ? .unverified : .failed, draft: entry.state, authored: nil, error: error,
                         evidence: evidence + ["write: \(error)"],
                         userMessage: error == .timedOut ? "Mail didn't answer in time. Say “what does the draft say?” to check." : error.userMessage)
        }
        switch write {
        case .changed:
            return .init(status: .failed, draft: entry.state, authored: base.authored, error: .draftChanged,
                         evidence: evidence + ["compare-and-set refused: the text changed outside Flow"], userMessage: MailError.draftChanged.userMessage)
        case .notFound:
            entries[id] = nil
            return .init(status: .failed, draft: nil, authored: nil, error: .draftGone, evidence: evidence, userMessage: MailError.draftGone.userMessage)
        case .ambiguous(let n):
            return .init(status: .failed, draft: entry.state, authored: base.authored, error: .draftAmbiguous(n),
                         evidence: evidence + ["\(n) drafts match equally; nothing written"], userMessage: MailError.draftAmbiguous(n).userMessage)
        case .written(let content):
            evidence.append("compare-and-set write accepted (base version \(baseVersion))")
            let readBack = AuthoredText.split(content)
            let scriptOK = readBack.authored == newText && readBack.quoted == base.quoted
            evidence.append("scripting read-back is exactly the new text, quote preserved: \(scriptOK)")
            // On-screen proof: the same window shows the new text with unchanged recipients.
            var view: MailComposeView?
            if let inspector {
                let want = ComposeParser.normalize(newText)
                let deadline = ContinuousClock.now + configuration.verifyTimeout
                repeat {
                    let views = inspector.compose(titled: entry.state.subject)
                    if case .one(let v) = Self.select(views, token: entry.windowToken, names: [entry.senderName] + entry.state.recipients),
                       ComposeParser.normalize(v.body).contains(want) || want.isEmpty { view = v; break }
                    try? await Task.sleep(for: configuration.pollInterval)
                } while ContinuousClock.now < deadline
            }
            let recipientsOK = view.map { Self.recipientMatches($0, names: [entry.senderName] + entry.state.recipients) } ?? false
            evidence.append(view == nil ? "compose window does not show the new text" : "compose window shows the new text; To \(view!.to), Cc \(view!.cc)")
            entry.content = content
            entry.state = MailDraftState(id: id, recipients: entry.state.recipients, visibleRecipients: view?.to ?? entry.state.visibleRecipients,
                                         subject: entry.state.subject, body: ComposeParser.normalize(view?.body ?? content),
                                         version: entry.state.version + 1, inReplyTo: entry.state.inReplyTo)
            entries[id] = entry
            let ok = scriptOK && view != nil && recipientsOK
            return .init(status: ok ? .completed : .unverified, draft: entry.state, authored: readBack.authored, error: nil, evidence: evidence,
                         userMessage: ok ? "The draft is updated, not sent." : "I changed the draft but couldn't confirm it on screen. Check it before sending.")
        }
    }

    private func liveDetail(_ entry: Entry) async -> Result<OpenDraftDetail, MailError> {
        let details: [OpenDraftDetail]
        do throws(MailError) { details = try await backend.draftDetails(subject: entry.state.subject) } catch { return .failure(error) }
        let mine = details.filter { $0.to + $0.cc + $0.bcc == entry.state.recipients }
        if mine.count == 1 { return .success(mine[0]) }
        if mine.count > 1 {
            // Exact text last read or written by Flow; else the text last verified on screen.
            let same = entry.content.map { known in mine.filter { $0.content == known } }
                ?? mine.filter { ComposeParser.normalize($0.content) == ComposeParser.normalize(entry.state.body) }
            if same.count == 1 { return .success(same[0]) }
            return .failure(.draftAmbiguous(mine.count))
        }
        return .failure(mine.isEmpty ? (details.isEmpty ? .draftGone : .draftChanged) : .draftAmbiguous(mine.count))
    }

    // MARK: Helpers

    private func register(key: String, subject: String, to: [String], view: MailComposeView?, ref: MailMessageRef,
                          senderName: String, fallbackBody: String = "") -> MailDraftState {
        let id = byKey[key] ?? "mail-draft-\(UUID().uuidString)"
        let state = MailDraftState(id: id, recipients: to, visibleRecipients: view?.to ?? [], subject: subject,
                                   body: ComposeParser.normalize(view?.body ?? fallbackBody), version: 1, inReplyTo: ref)
        entries[id] = Entry(state: state, senderName: senderName, windowToken: view?.windowToken)
        byKey[key] = id
        return state
    }

    /// Polls Accessibility until exactly one compose window shows what was requested. Windows
    /// are chosen by recipients and body, never by title alone; equal matches are ambiguous.
    private func waitForCompose(_ subject: String, expecting text: String, senderName: String, sender: String)
        async -> (ok: Bool, view: MailComposeView?, notes: [String], ambiguous: Int?)
    {
        guard let inspector else { return (false, nil, ["no Accessibility inspector: contents not verified on screen"], nil) }
        let want = ComposeParser.normalize(text)
        let names = [senderName, sender]
        let deadline = ContinuousClock.now + configuration.verifyTimeout
        var views: [MailComposeView] = []
        var selection = ComposeSelection.none
        repeat {
            views = inspector.compose(titled: subject)
            selection = Self.select(views, token: nil, names: names, require: want)
            if case .one = selection { break }
            try? await Task.sleep(for: configuration.pollInterval)
        } while ContinuousClock.now < deadline
        switch selection {
        case .one(let v):
            let notes = [
                "on screen: To \(v.to), Cc \(v.cc), subject matches: \(v.subject == subject)",
                "requested text visible in the body: true",
                views.count > 1 ? "\(views.count) windows titled “\(subject)”; exactly one has these recipients and this text" : nil,
            ].compactMap { $0 }
            return (true, v, notes, nil)
        case .ambiguous(let n):
            return (false, nil, ["\(n) compose windows titled “\(subject)” match equally; not guessing which is Flow's"], n)
        case .none:
            guard views.count == 1, let v = views.first else {
                return (false, nil, ["compose windows titled “\(subject)” on screen: \(views.count); none shows these recipients and this text"], nil)
            }
            let notes = [
                "on screen: To \(v.to), Cc \(v.cc), subject matches: \(v.subject == subject)",
                "requested text visible in the body: \(ComposeParser.normalize(v.body).contains(want))",
            ]
            return (false, v, notes, nil)
        }
    }

    public enum ComposeSelection: Sendable, Equatable {
        case none
        case one(MailComposeView)
        case ambiguous(Int)
    }

    /// Chooses Flow's compose window among windows with the same title (pure, unit-tested).
    /// 1. A known window identity (`token`) decides, whatever the window now shows.
    /// 2. Otherwise only windows addressed to exactly the sender (one To token, no Cc) that
    ///    show `require` count; if several remain, one whose body equals `prefer` wins.
    /// 3. Several equal matches are `.ambiguous`: never guessed, never "the first one".
    public static func select(_ views: [MailComposeView], token: Int?, names: [String], require: String? = nil,
                              prefer: String? = nil) -> ComposeSelection {
        if let token {
            let same = views.filter { $0.windowToken == token }
            if same.count == 1 { return .one(same[0]) }
            if same.count > 1 { return .ambiguous(same.count) }
        }
        let want = require.map(ComposeParser.normalize)
        let strict = views.filter { v in
            recipientMatches(v, names: names) && (want.map { ComposeParser.normalize(v.body).contains($0) } ?? true)
        }
        if strict.count > 1, let prefer {
            let p = ComposeParser.normalize(prefer)
            let exact = strict.filter { ComposeParser.normalize($0.body) == p }
            if exact.count == 1 { return .one(exact[0]) }
        }
        switch strict.count {
        case 0: return .none
        case 1: return .one(strict[0])
        default: return .ambiguous(strict.count)
        }
    }

    static func recipientMatches(_ v: MailComposeView, names: [String]) -> Bool {
        guard v.to.count == 1, v.cc.isEmpty else { return false }
        let token = v.to[0].lowercased()
        let names = names.map { $0.lowercased() }.filter { !$0.isEmpty }
        return names.contains { token == $0 || token.contains($0) || $0.contains(token) }
    }

    static func matches(_ v: MailComposeView, text: String, senderName: String, sender: String) -> Bool {
        ComposeParser.normalize(v.body).contains(text) && recipientMatches(v, names: [senderName, sender])
    }

    private func waitForVisible(_ subject: String) async -> [MailComposeView] {
        guard let inspector else { return [] }
        let deadline = ContinuousClock.now + configuration.verifyTimeout
        var views: [MailComposeView] = []
        repeat {
            views = inspector.compose(titled: subject)
            if !views.isEmpty { break }
            try? await Task.sleep(for: configuration.pollInterval)
        } while ContinuousClock.now < deadline
        return views
    }

    private func failure(_ error: MailError, evidence: [String] = []) -> MailDraftResult {
        MailDraftResult(status: error == .emptyContent || error == .noReplyAddress ? .unsupported : .failed, draft: nil, error: error,
                        evidence: evidence, userMessage: error.userMessage)
    }
}
