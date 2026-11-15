@testable import FlowMail
import FlowMailSend
import Foundation

/// Simulated Mail sending over `FakeDraftBackend`'s open drafts. Never touches real Mail.
@MainActor
final class FakeSendTransport: MailSendTransport {
    enum Behavior {
        case sends            // Mail sends: draft closes, message appears in Sent
        case queues           // draft closes, message waits in the Outbox
        case returnsFalse     // Mail reports failure; draft stays open
        case throwsAfterSend  // the script errors after `send` was called (unknown outcome)
        case closesSilently   // draft closes, nothing in Sent or Outbox (unknown outcome)
    }

    let drafts: FakeDraftBackend
    var behavior: Behavior = .sends
    /// Called inside `send` before the re-check (simulates a last-moment edit).
    var beforeSend: (() -> Void)?
    private(set) var sendCalls = 0
    private(set) var sent: [(subject: String, to: [String], body: String)] = []
    private(set) var outbox: [(subject: String, to: [String])] = []

    init(drafts: FakeDraftBackend) { self.drafts = drafts }

    func outgoing(subject: String) async throws(MailError) -> [OutgoingDraft] {
        drafts.open.filter { $0.subject == subject }.map {
            OutgoingDraft(subject: $0.subject, to: $0.to, cc: $0.cc, bcc: $0.bcc, digest: "\($0.body.count):\($0.body)")
        }
    }

    func send(subject: String, expected: OutgoingDraft) async throws(MailError) -> SendDispatch {
        beforeSend?()
        let matching = drafts.open.indices.filter { drafts.open[$0].subject == subject }
        guard matching.count == 1, let i = matching.first else { return .refused("count:\(matching.count)") }
        let d = drafts.open[i]
        guard d.to.sorted() == expected.to.sorted(), d.cc.isEmpty, d.bcc.isEmpty, "\(d.body.count):\(d.body)" == expected.digest else {
            return .refused("changed")
        }
        sendCalls += 1
        switch behavior {
        case .sends:
            drafts.open.remove(at: i)
            sent.append((subject, d.to, d.body))
            return .dispatched(mailReturned: true)
        case .queues:
            drafts.open.remove(at: i)
            outbox.append((subject, d.to))
            return .dispatched(mailReturned: true)
        case .returnsFalse:
            return .dispatched(mailReturned: false)
        case .throwsAfterSend:
            throw .timedOut
        case .closesSilently:
            drafts.open.remove(at: i)
            return .dispatched(mailReturned: true)
        }
    }

    func evidence(subject: String, recipients: [String], since: Date) async throws(MailError) -> SendEvidence {
        SendEvidence(stillOpen: drafts.open.filter { $0.subject == subject }.count,
                     inSent: sent.contains { $0.subject == subject && Set(recipients).isSubset(of: Set($0.to)) },
                     inOutbox: outbox.contains { $0.subject == subject && Set(recipients).isSubset(of: Set($0.to)) })
    }
}
