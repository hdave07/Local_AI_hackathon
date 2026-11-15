import AppKit
import CoreServices
import FlowAX
import FlowWindow
import Foundation

/// Real backend: Mail's supported scripting interface (JavaScript for Automation via
/// `osascript`), read-only. Every request is one JSON argument; the script never
/// evaluates caller-supplied text as code.
@MainActor
public final class JXAMailBackend: MailBackend, MailDraftBackend {
    public nonisolated static let bundleID = "com.apple.mail"
    private let runner: ScriptRunning
    private let timeout: Duration

    public init(runner: ScriptRunning = OSAScriptRunner(), timeout: Duration = .seconds(30)) {
        self.runner = runner
        self.timeout = timeout
    }

    // MARK: Availability

    /// A successful readiness check is reused briefly so each command doesn't re-query Mail.
    private var readyUntil: ContinuousClock.Instant?
    private var lastReady: MailAvailability?

    public func availability(requestPermission: Bool) async -> MailAvailability {
        if let readyUntil, let lastReady, ContinuousClock.now < readyUntil,
            !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        {
            return lastReady
        }
        let value = await checkAvailability(requestPermission: requestPermission)
        if case .ready = value {
            lastReady = value
            readyUntil = ContinuousClock.now + .seconds(60)
        } else {
            lastReady = nil
            readyUntil = nil
        }
        return value
    }

    private func checkAvailability(requestPermission: Bool) async -> MailAvailability {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return .notInstalled }
        if NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
            guard requestPermission else { return .notRunning }
            // Launch in the background (no UI change) so Automation consent can be checked.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<50 where NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        switch await Self.automationPermission(ask: requestPermission) {
        case noErr: break
        case OSStatus(errAEEventNotPermitted): return .automationDenied
        case OSStatus(errAEEventWouldRequireUserConsent): return .automationNotDetermined
        case OSStatus(procNotFound): return .notRunning
        default: return .automationDenied
        }
        do throws(MailError) {
            let reply: StatusReply = try await call(["op": "status"])
            return reply.accounts > 0 ? .ready(accounts: reply.accounts) : .noAccounts
        } catch {
            if error == .automationDenied { return .automationDenied }
            if error == .automationNotDetermined { return .automationNotDetermined }
            return .notRunning
        }
    }

    /// AEDeterminePermissionToAutomateTarget can block on the consent prompt, so run it off the main actor.
    nonisolated static func automationPermission(ask: Bool) async -> OSStatus {
        await Task.detached {
            var target = AEAddressDesc()
            let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
            guard created == noErr else { return OSStatus(created) }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
        }.value
    }

    // MARK: Read-only operations

    public func search(_ query: MailQuery) async throws(MailError) -> MailSearchResult {
        var request: [String: Any] = ["op": "search", "limit": query.limit, "terms": query.terms]
        if let s = query.sender { request["sender"] = s }
        if let s = query.subject { request["subject"] = s }
        if let m = query.mailbox { request["mailbox"] = m }
        let reply: SearchReply = try await call(request)
        return MailSearchResult(messages: reply.messages.map(\.summary), total: reply.total)
    }

    public func lookup(_ ref: MailMessageRef) async throws(MailError) -> MailMessageSummary {
        let reply: MessageWire = try await call(["op": "lookup", "ref": Self.encode(ref)])
        return reply.summary
    }

    public func lookupWithContent(_ ref: MailMessageRef) async throws(MailError) -> (MailMessageSummary, String) {
        let reply: MessageWithContent = try await call(["op": "lookup", "ref": Self.encode(ref), "withContent": true])
        return (reply.message.summary, reply.content)
    }

    public func open(_ ref: MailMessageRef, expectedSubject: String) async throws(MailError) -> MailOpenOutcome {
        let reply: OpenReply = try await call(["op": "open", "ref": Self.encode(ref), "subject": expectedSubject])
        return MailOpenOutcome(frontWindow: reply.frontWindow, isReadAfter: reply.read)
    }

    public func content(_ ref: MailMessageRef) async throws(MailError) -> String {
        let reply: ContentReply = try await call(["op": "content", "ref": Self.encode(ref)])
        return reply.content
    }

    // MARK: Drafts (no send, save or delete)

    public func createReplyDraft(_ ref: MailMessageRef, recipient: String, content: String) async throws(MailError) -> ReplyCreation {
        let reply: ReplyDraftReply = try await call(["op": "replyDraft", "ref": Self.encode(ref), "recipient": recipient, "content": content])
        if let existing = reply.existing {
            return .existing(subject: reply.subject, drafts: existing.map { OpenDraftInfo(to: $0.to, cc: $0.cc, bcc: $0.bcc) })
        }
        if reply.mismatch == true { return .mismatch(to: reply.to ?? [], cc: reply.cc ?? [], bcc: reply.bcc ?? []) }
        return .created(subject: reply.subject, to: reply.to ?? [], cc: reply.cc ?? [], bcc: reply.bcc ?? [],
                        contentSet: reply.contentSet ?? false, windowShown: reply.window != nil)
    }

    public func openDrafts(subject: String) async throws(MailError) -> [OpenDraftInfo] {
        let reply: DraftsReply = try await call(["op": "drafts", "subject": subject])
        return reply.drafts.map { OpenDraftInfo(to: $0.to, cc: $0.cc, bcc: $0.bcc) }
    }

    public func showDraft(subject: String) async throws(MailError) -> Int {
        let reply: ShowReply = try await call(["op": "showDraft", "subject": subject])
        return reply.count
    }

    struct AddressLists: Decodable {
        let to: [String]
        let cc: [String]
        let bcc: [String]
    }

    struct ReplyDraftReply: Decodable {
        let subject: String
        let existing: [AddressLists]?
        let mismatch: Bool?
        let to: [String]?
        let cc: [String]?
        let bcc: [String]?
        let contentSet: Bool?
        let window: String?
    }

    struct DraftsReply: Decodable { let drafts: [AddressLists] }
    struct ShowReply: Decodable { let count: Int }

    // MARK: Transport

    private func call<T: Decodable>(_ request: [String: Any]) async throws(MailError) -> T {
        guard let json = try? JSONSerialization.data(withJSONObject: request),
            let argument = String(data: json, encoding: .utf8)
        else { throw .invalidQuery("Couldn't encode the request.") }
        let data = try await runner.run(javaScript: Self.script, argument: argument, timeout: timeout)
        return try Self.decode(data)
    }

    nonisolated static func decode<T: Decodable>(_ data: Data) throws(MailError) -> T {
        let decoder = JSONDecoder()
        if let failure = try? decoder.decode(ScriptFailure.self, from: data) {
            switch failure.error {
            case "mailboxNotFound": throw .mailboxNotFound(failure.name ?? "")
            case "ambiguousMailbox": throw .ambiguousMailbox(failure.name ?? "", paths: failure.paths ?? [])
            case "gone": throw .messageGone
            default: throw .scriptFailure(code: 0)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .scriptFailure(code: -1)
        }
    }

    nonisolated static func encode(_ ref: MailMessageRef) -> [String: Any] {
        ["account": ref.mailbox.account as Any, "path": ref.mailbox.path, "id": ref.internalID, "messageID": ref.messageID]
    }

    // MARK: Wire types

    struct ScriptFailure: Decodable {
        let error: String
        let name: String?
        let paths: [String]?
    }

    struct StatusReply: Decodable { let accounts: Int }

    struct MessageWire: Decodable {
        let id: Int
        let messageID: String
        let subject: String
        let sender: String
        let date: String?
        let read: Bool
        let account: String?
        let path: String

        var summary: MailMessageSummary {
            let (name, address) = MailMessageSummary.splitSender(sender)
            return MailMessageSummary(
                ref: MailMessageRef(messageID: messageID, mailbox: MailboxRef(account: account, path: path), internalID: id),
                senderName: name, senderAddress: address, subject: subject,
                dateReceived: date.flatMap { JXAMailBackend.isoFormatter.date(from: $0) }, isRead: read)
        }
    }

    struct SearchReply: Decodable {
        let total: Int
        let messages: [MessageWire]
    }

    struct OpenReply: Decodable {
        let frontWindow: String?
        let read: Bool?
    }

    struct MessageWithContent: Decodable {
        let message: MessageWire
        let content: String
    }
    struct ContentReply: Decodable { let content: String }

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Script

    /// One dispatching script. Read-only except `open`, which only opens a viewer window.
    nonisolated static let script = #"""
    function run(argv) {
      const req = JSON.parse(argv[0]);
      const Mail = Application('com.apple.mail');
      const fail = (code, extra) => JSON.stringify(Object.assign({ error: code }, extra || {}));

      function accountOf(b) { try { return b.account().name(); } catch (e) { return null; } }
      function pathOf(b) {
        const parts = [b.name()];
        let c = b;
        for (let i = 0; i < 12; i++) {
          try { c = c.container(); parts.unshift(c.name()); } catch (e) { break; }
        }
        return parts.join('/');
      }
      // Mailboxes of one scope: account === undefined → all; null → local ("On My Mac"); name → that account.
      function mailboxesIn(account) {
        const list = [];
        if (account === undefined || account === null) Mail.mailboxes().forEach(b => list.push({ box: b, account: null }));
        if (account !== null) {
          for (const a of Mail.accounts()) {
            const name = a.name();
            if (account !== undefined && name !== account) continue;
            let boxes = [];
            try { boxes = a.mailboxes(); } catch (e) {}
            for (const b of boxes) list.push({ box: b, account: name });
          }
        }
        return list;
      }
      function findMailboxes(spec) {
        const want = spec.toLowerCase();
        const byPath = want.indexOf('/') >= 0;
        const seen = {};
        const hits = [];
        const leaf = want.split('/').pop();
        for (const e of mailboxesIn(undefined)) {
          if (e.box.name().toLowerCase() !== leaf) continue;  // cheap name test before walking the path
          const path = pathOf(e.box);
          const key = (e.account || '') + '|' + path;
          if (seen[key]) continue;
          seen[key] = true;
          if (!byPath || path.toLowerCase() === want) hits.push({ box: e.box, account: e.account, path: path });
        }
        return hits;
      }
      function resolveRef(ref) {
        const leaf = ref.path.split('/').pop();
        for (const e of mailboxesIn(ref.account || null)) {
          if (e.box.name() !== leaf) continue;
          if (pathOf(e.box) === ref.path) return e.box;
        }
        return null;
      }
      function messageAt(ref) {
        const box = resolveRef(ref);
        if (!box) return null;
        const s = box.messages.whose({ id: ref.id });
        return s.length > 0 ? s[0] : null;
      }
      function summarize(m, account, path) {
        const d = m.dateReceived();
        return { id: m.id(), messageID: m.messageId(), subject: m.subject() || '', sender: m.sender() || '',
                 date: d ? d.toISOString() : null, read: m.readStatus(), account: account, path: path };
      }

      if (req.op === 'status') return JSON.stringify({ accounts: Mail.accounts().length });

      if (req.op === 'search') {
        let box, fixed = null;
        if (req.mailbox) {
          const hits = findMailboxes(req.mailbox);
          if (hits.length === 0) return fail('mailboxNotFound', { name: req.mailbox });
          if (hits.length > 1) return fail('ambiguousMailbox', { name: req.mailbox, paths: hits.map(h => (h.account || 'On My Mac') + '/' + h.path) });
          box = hits[0].box;
          fixed = { account: hits[0].account, path: hits[0].path };
        } else {
          box = Mail.inbox;
        }
        const conds = [];
        if (req.sender) conds.push({ sender: { _contains: req.sender } });
        if (req.subject) conds.push({ subject: { _contains: req.subject } });
        for (const t of req.terms) conds.push({ _or: [{ subject: { _contains: t } }, { sender: { _contains: t } }] });
        const s = box.messages.whose(conds.length === 1 ? conds[0] : { _and: conds });
        const ids = s.id();
        if (ids.length === 0) return JSON.stringify({ total: 0, messages: [] });
        const dates = s.dateReceived();
        const order = ids.map((_, i) => i).sort((a, b) => (dates[b] || 0) - (dates[a] || 0)).slice(0, req.limit);
        const messages = [];
        for (const i of order) {
          const m = s[i];
          if (m.id() !== ids[i]) continue;  // mailbox changed while reading; skip rather than mislabel
          let account = fixed ? fixed.account : null, path = fixed ? fixed.path : null;
          if (!fixed) { const mb = m.mailbox(); account = accountOf(mb); path = pathOf(mb); }
          messages.push(summarize(m, account, path));
        }
        return JSON.stringify({ total: ids.length, messages: messages });
      }

      if (req.op === 'lookup' || req.op === 'open' || req.op === 'content') {
        const m = messageAt(req.ref);
        if (!m) return fail('gone');
        if (req.op === 'lookup') {
          const summary = summarize(m, req.ref.account, req.ref.path);
          if (req.withContent) return JSON.stringify({ message: summary, content: m.content() || '' });
          return JSON.stringify(summary);
        }
        if (req.op === 'content') return JSON.stringify({ content: m.content() || '' });
        Mail.open(m);
        Mail.activate();
        let front = null;
        for (let i = 0; i < 20; i++) {
          delay(0.1);
          try { front = Mail.windows[0].name(); } catch (e) { front = null; }
          if (front && req.subject && front.indexOf(req.subject) === 0) break;
        }
        return JSON.stringify({ frontWindow: front, read: m.readStatus() });
      }
      // ---- Reply drafts. There is no send, save or delete operation in this script. ----
      const addrs = list => list.map(x => { try { return (x.address() || '').toLowerCase(); } catch (e) { return ''; } });
      const openWithSubject = subject => Mail.outgoingMessages().filter(o => { try { return o.subject() === subject; } catch (e) { return false; } });
      const lists = o => ({ to: addrs(o.toRecipients()), cc: addrs(o.ccRecipients()), bcc: addrs(o.bccRecipients()) });

      if (req.op === 'replyDraft') {
        const m = messageAt(req.ref);
        if (!m) return fail('gone');
        const original = m.subject() || '';
        const expectedSubject = /^re:/i.test(original) ? original : 'Re: ' + original;
        const open = openWithSubject(expectedSubject);
        if (open.length > 0) return JSON.stringify({ subject: expectedSubject, existing: open.map(lists) });
        // Hidden first: recipients are checked before anything is shown. Reply-all is off.
        const r = Mail.reply(m, { openingWindow: false, replyToAll: false });
        const l = lists(r);
        const want = String(req.recipient || '').toLowerCase();
        if (l.to.length !== 1 || l.to[0] !== want || l.cc.length || l.bcc.length) {
          try { r.close({ saving: 'no' }); } catch (e) {}  // never shown, never saved
          return JSON.stringify({ subject: expectedSubject, mismatch: true, to: l.to, cc: l.cc, bcc: l.bcc });
        }
        r.content = req.content;
        const set = String(r.content() || '');
        r.visible = true;
        Mail.activate();
        const subject = r.subject();
        let shown = null;
        for (let i = 0; i < 30 && !shown; i++) {
          delay(0.1);
          try { const w = Mail.windows().filter(w => w.visible() && w.name() === subject); if (w.length) shown = w[0].name(); } catch (e) {}
        }
        return JSON.stringify({ subject: subject, to: l.to, cc: l.cc, bcc: l.bcc,
                                contentSet: set.replace(/\s+/g, ' ').indexOf(String(req.content).trim().replace(/\s+/g, ' ')) >= 0,
                                window: shown });
      }

      if (req.op === 'drafts') return JSON.stringify({ drafts: openWithSubject(req.subject).map(lists) });

      if (req.op === 'showDraft') {
        const open = openWithSubject(req.subject);
        if (open.length !== 1) return JSON.stringify({ count: open.length });
        open[0].visible = true;
        try { const w = Mail.windows().filter(w => w.visible() && w.name() === req.subject); if (w.length === 1) w[0].index = 1; } catch (e) {}
        Mail.activate();
        delay(0.3);
        return JSON.stringify({ count: 1 });
      }

      return fail('unknownOp');
    }
    """#
}

/// Verifies what Mail displays using FlowAX (Accessibility). Reports booleans only;
/// no on-screen text is stored or logged.
@MainActor
public final class AXMailDisplayVerifier: MailDisplayVerifying {
    private let backend: AXUIBackend

    public init(backend: AXUIBackend = AXUIBackend(frontmost: { nil })) {
        self.backend = backend
    }

    public func observe(subject: String, bodySnippet: String?) async -> (windowMatches: Bool, bodyVisible: Bool) {
        guard let app = try? backend.resolveApp(.named(JXAMailBackend.bundleID)),
            let snapshot = try? backend.observe(app, limits: SnapshotLimits())
        else { return (false, false) }
        let windowMatches = !subject.isEmpty && snapshot.windowTitle.hasPrefix(subject)
        guard let snippet = bodySnippet.map(LabelText.clean), !snippet.isEmpty else { return (windowMatches, false) }
        let bodyVisible = snapshot.elements.contains { e in
            e.isVisible && ((e.value ?? "").contains(snippet) || e.label.contains(snippet))
        }
        return (windowMatches, bodyVisible)
    }
}
