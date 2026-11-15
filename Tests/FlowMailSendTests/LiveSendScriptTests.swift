import FlowMail
@testable import FlowMailSend
import Foundation
import Testing

/// FLOW_LIVE_MAIL=1: runs the sending script's read-only operations against real Mail for a
/// subject that cannot exist. Never calls `send`, never reads a real message.
@MainActor
@Suite("Live: send script read-only operations", .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_MAIL"] == "1"))
struct LiveSendScriptTests {
    @Test func outgoingAndEvidenceRunAgainstRealMail() async throws {
        let subject = "FLOWTEST-NONEXISTENT-\(UUID().uuidString)"
        let t = JXAMailSendTransport()
        let open = try await t.outgoing(subject: subject)
        #expect(open.isEmpty)
        let e = try await t.evidence(subject: subject, recipients: ["nobody@example.invalid"], since: Date())
        #expect(e == SendEvidence(stillOpen: 0, inSent: false, inOutbox: false))
    }
}
