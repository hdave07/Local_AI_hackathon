import FlowMail
import Foundation

/// Mail's supported scripting interface for sending (JXA via `osascript`; every request is one
/// JSON argument). Uses only `outgoing message` properties, the `send` command (boolean
/// result), and the `sent mailbox` / `outbox` properties from Mail's dictionary.
///
/// `send` re-checks recipients and content inside the same script that sends, so the draft
/// cannot change between the check and the send. Nothing here saves, deletes or edits.
@MainActor
public final class JXAMailSendTransport: MailSendTransport {
    private let runner: ScriptRunning
    private let timeout: Duration

    public init(runner: ScriptRunning = OSAScriptRunner(), timeout: Duration = .seconds(30)) {
        self.runner = runner
        self.timeout = timeout
    }

    struct DraftsReply: Decodable { let drafts: [OutgoingDraft] }
    struct SendReply: Decodable {
        let refused: String?
        let dispatched: Bool?
        let result: Bool?
    }
    struct EvidenceReply: Decodable {
        let stillOpen: Int
        let inSent: Bool
        let inOutbox: Bool
    }

    public func outgoing(subject: String) async throws(MailError) -> [OutgoingDraft] {
        let r: DraftsReply = try await call(["op": "outgoing", "subject": subject])
        return r.drafts
    }

    public func send(subject: String, expected: OutgoingDraft) async throws(MailError) -> SendDispatch {
        let e: [String: Any] = ["to": expected.to, "cc": expected.cc, "bcc": expected.bcc, "digest": expected.digest,
                                "text": expected.text ?? ""]
        let r: SendReply = try await call(["op": "send", "subject": subject, "expected": e])
        if let why = r.refused { return .refused(why) }
        return .dispatched(mailReturned: r.result)
    }

    public func evidence(subject: String, recipients: [String], since: Date) async throws(MailError) -> SendEvidence {
        let r: EvidenceReply = try await call(["op": "evidence", "subject": subject, "recipients": recipients,
                                               "since": since.timeIntervalSince1970 * 1000])
        return SendEvidence(stillOpen: r.stillOpen, inSent: r.inSent, inOutbox: r.inOutbox)
    }

    private func call<T: Decodable>(_ request: [String: Any]) async throws(MailError) -> T {
        guard let json = try? JSONSerialization.data(withJSONObject: request), let argument = String(data: json, encoding: .utf8)
        else { throw .invalidQuery("Couldn't encode the request.") }
        let data = try await runner.run(javaScript: Self.script, argument: argument, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .scriptFailure(code: -1)
        }
    }

    static let script = #"""
    function run(argv) {
      const req = JSON.parse(argv[0]);
      const Mail = Application('com.apple.mail');
      const addrs = list => list.map(x => { try { return (x.address() || '').toLowerCase(); } catch (e) { return ''; } });
      const open = s => Mail.outgoingMessages().filter(o => { try { return o.subject() === s; } catch (e) { return false; } });
      const digestOf = o => {
        let c = ''; try { c = String(o.content() || ''); } catch (e) {}
        c = c.replace(/\s+/g, ' ').trim();
        let h = 5381; for (let i = 0; i < c.length; i++) { h = ((h * 33) ^ c.charCodeAt(i)) >>> 0; }
        return c.length + ':' + h.toString(16);
      };
      const textOf = o => { try { return String(o.content() || '').slice(0, 20000); } catch (e) { return null; } };
      const info = o => ({ subject: o.subject(), to: addrs(o.toRecipients()), cc: addrs(o.ccRecipients()),
                           bcc: addrs(o.bccRecipients()), digest: digestOf(o), text: textOf(o) });
      const same = (a, b) => JSON.stringify(a.slice().sort()) === JSON.stringify(b.slice().sort());

      if (req.op === 'outgoing') return JSON.stringify({ drafts: open(req.subject).map(info) });

      if (req.op === 'send') {
        const list = open(req.subject);
        if (list.length !== 1) return JSON.stringify({ refused: 'count:' + list.length });
        const now = info(list[0]), e = req.expected;
        if (!same(now.to, e.to) || now.cc.length || now.bcc.length || e.cc.length || e.bcc.length || now.digest !== e.digest) {
          return JSON.stringify({ refused: 'changed' });
        }
        let ok = null;
        try { ok = Mail.send(list[0]); } catch (err) { return JSON.stringify({ dispatched: true, result: null }); }
        return JSON.stringify({ dispatched: true, result: ok === true });
      }

      if (req.op === 'evidence') {
        const since = new Date(req.since);
        const found = mb => {
          try {
            return mb.messages.whose({ subject: req.subject })().some(m => {
              try {
                const d = m.dateSent(); if (d && d < since) return false;
                const to = addrs(m.toRecipients());
                return req.recipients.every(r => to.indexOf(r) >= 0);
              } catch (e) { return false; }
            });
          } catch (e) { return false; }
        };
        return JSON.stringify({ stillOpen: open(req.subject).length, inSent: found(Mail.sentMailbox()), inOutbox: found(Mail.outbox()) });
      }
      return JSON.stringify({ error: 'unknownOp' });
    }
    """#
}
