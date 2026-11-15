import ApplicationServices
import AppKit
import FlowAX
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

    public init(title: String, to: [String], cc: [String], subject: String, body: String) {
        self.title = title
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
    }
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
            return ComposeParser.parse(title: title, window: Self.node(w, depth: 0))
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
        guard open.count == 1 else { return failure(.draftAmbiguous(open.count)) }
        if present {
            do throws(MailError) {
                let shown = try await backend.showDraft(subject: subject)
                guard shown == 1 else { return failure(shown == 0 ? .draftGone : .draftAmbiguous(shown)) }
            } catch {
                return failure(error)
            }
        }
        let views = await waitForVisible(subject)
        guard views.count <= 1 else { return failure(.draftAmbiguous(views.count)) }
        let view = views.first
        var evidence = prior
        let liveBody = view.map(\.body) ?? entry.state.body
        let live = (recipients: open[0].to + open[0].cc + open[0].bcc, body: ComposeParser.normalize(liveBody))
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

    // MARK: Helpers

    private func register(key: String, subject: String, to: [String], view: MailComposeView?, ref: MailMessageRef,
                          senderName: String, fallbackBody: String = "") -> MailDraftState {
        let id = byKey[key] ?? "mail-draft-\(UUID().uuidString)"
        let state = MailDraftState(id: id, recipients: to, visibleRecipients: view?.to ?? [], subject: subject,
                                   body: ComposeParser.normalize(view?.body ?? fallbackBody), version: 1, inReplyTo: ref)
        entries[id] = Entry(state: state, senderName: senderName)
        byKey[key] = id
        return state
    }

    /// Polls Accessibility until the compose window shows exactly what was requested.
    private func waitForCompose(_ subject: String, expecting text: String, senderName: String, sender: String)
        async -> (ok: Bool, view: MailComposeView?, notes: [String])
    {
        guard let inspector else { return (false, nil, ["no Accessibility inspector: contents not verified on screen"]) }
        let want = ComposeParser.normalize(text)
        let deadline = ContinuousClock.now + configuration.verifyTimeout
        var views: [MailComposeView] = []
        repeat {
            views = inspector.compose(titled: subject)
            if views.count == 1, Self.matches(views[0], text: want, senderName: senderName, sender: sender) { break }
            try? await Task.sleep(for: configuration.pollInterval)
        } while ContinuousClock.now < deadline
        guard views.count == 1, let v = views.first else {
            return (false, nil, ["compose windows titled “\(subject)” on screen: \(views.count)"])
        }
        let notes = [
            "on screen: To \(v.to), Cc \(v.cc), subject matches: \(v.subject == subject)",
            "requested text visible in the body: \(ComposeParser.normalize(v.body).contains(want))",
        ]
        return (Self.matches(v, text: want, senderName: senderName, sender: sender), v, notes)
    }

    static func matches(_ v: MailComposeView, text: String, senderName: String, sender: String) -> Bool {
        guard v.to.count == 1, v.cc.isEmpty, ComposeParser.normalize(v.body).contains(text) else { return false }
        let token = v.to[0].lowercased()
        let names = [senderName.lowercased(), sender.lowercased()].filter { !$0.isEmpty }
        return names.contains { token == $0 || token.contains($0) || $0.contains(token) }
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
