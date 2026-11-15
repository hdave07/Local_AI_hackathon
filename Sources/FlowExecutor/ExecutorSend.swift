import FlowCore
import FlowMail
import FlowMailSend
import FlowPlanner
import FlowRouting
import Foundation

// T-023C (ADR 0010): `request_send` for Mail. The planner only sends this request after an
// explicit spoken yes, with a single-use `Approval` bound to draft id, version and content
// hash. Here, immediately before sending, the live draft is re-read on screen and must
// still match that approval exactly; then `MailSender` re-checks Mail's own view of the
// draft and dispatches at most once.
extension ExecutorEngine {
    func send(_ request: ExecutionRequest) async -> ExecutionResult {
        guard let sender, sender.mode != .disabled else {
            return Self.unsupported("Sending is disabled in this version. Nothing was sent.")
        }
        guard (request.channel ?? .mail) == .mail else {
            return Self.unsupported("Only Mail sending is supported; \(request.channel!.rawValue) isn't connected. Nothing was sent.")
        }
        guard let drafts else { return Self.unsupported("Drafts aren't enabled, so there's nothing to send.") }

        // 1. An explicit, unexpired approval of exactly the bound draft state.
        guard let approval = request.bindings.approval, let bound = request.bindings.draft else {
            return refuse(.approvalInvalid, "I need your explicit confirmation before sending.")
        }
        guard approval.authorizes(.send, on: bound, now: Date()) else {
            return refuse(.approvalInvalid, "That confirmation no longer matches the draft or has expired.")
        }
        guard bound.channel == .mail, drafts.state(bound.id) != nil else {
            return refuse(.targetNotFound, "I don't have that draft open any more.")
        }
        if Task.isCancelled { return ExecutionResult(status: .cancelled, userMessage: "Cancelled before sending. Nothing was sent.") }

        // 2. The draft as it is on screen *now* (recipients via scripting, body via Accessibility).
        let live = await drafts.refresh(bound.id, present: true)
        guard live.status == .completed, let state = live.draft else {
            switch live.error {
            case .draftAmbiguous(let n)?:
                return refuse(.draftAlreadyOpen, "There are \(n) drafts with this subject open, so I won't send until only one is.")
            case .draftGone?, .unknownDraft?:
                return refuse(.targetNotFound, "The draft is no longer open.")
            case .automationDenied?, .automationNotDetermined?:
                return refuse(.permissionDenied, "Flow isn't allowed to control Mail.")
            default:
                return refuse(.approvalInvalid, "I couldn't re-check the draft on screen just now.")
            }
        }
        let snapshot = DraftSnapshot(channel: .mail, id: state.id, recipients: state.recipients, subject: state.subject,
                                     body: state.body, version: state.version, inReplyTo: bound.inReplyTo)
        guard snapshot.version == approval.draftVersion, snapshot.contentHash == approval.contentHash else {
            // Any edit after approval (in Mail, by FlowText, anywhere) invalidates it.
            return ExecutionResult(status: .failed, observation: .draft(snapshot), error: .draftChanged,
                                   userMessage: "The draft changed after you approved it.")
        }
        if Task.isCancelled { return ExecutionResult(status: .cancelled, userMessage: "Cancelled before sending. Nothing was sent.") }

        // 3. Dispatch at most once and classify the outcome.
        let outcome = await sender.send(ApprovedSend(
            approvalID: approval.id, draftID: snapshot.id, subject: snapshot.subject, recipients: snapshot.recipients,
            version: snapshot.version, contentHash: snapshot.contentHash))
        let to = snapshot.recipients.joined(separator: ", ")
        switch outcome {
        case .accepted(let queued, _):
            return ExecutionResult(status: .completed, observation: .sent(draftID: snapshot.id, queued: queued),
                                   userMessage: queued
                                       ? "Mail accepted the message to \(to), but it's still in the Outbox."
                                       : "Mail sent it to \(to). It's in your Sent mailbox; I can't confirm delivery.")
        case .rehearsed:
            return ExecutionResult(status: .completed, observation: .sendRehearsed(draftID: snapshot.id),
                                   userMessage: "Dry run: would have sent to \(to). Nothing was sent.")
        case .notSent:
            return ExecutionResult(status: .failed, error: .notSent,
                                   userMessage: "Mail reported it couldn't send the message. The draft is still open.")
        case .unknown:
            return ExecutionResult(status: .unverified,
                                   userMessage: "I couldn't confirm whether Mail sent it. Check your Sent mailbox before trying again.")
        case .refused(let why, _):
            switch why {
            case .disabled: return Self.unsupported("Sending is disabled in this version. Nothing was sent.")
            case .alreadyDispatched:
                // Never "nothing was sent": an earlier attempt may have gone out. The runner records it as unverified.
                return ExecutionResult(status: .failed, error: .unknown,
                                       userMessage: "That draft was already sent or attempted, so I won't send it again.")
            case .ambiguousDraft(let n): return refuse(.draftAlreadyOpen, "There are \(n) drafts with this subject open, so I won't send until only one is.")
            case .draftGone: return refuse(.targetNotFound, "The draft is no longer open.")
            case .recipientMismatch: return refuse(.recipientMismatch, "Mail's draft has different or extra recipients than you approved.")
            case .recipientNotAllowed: return refuse(.recipientMismatch, "That recipient isn't on the live-test allowlist.")
            case .contentChanged: return refuse(.draftChanged, "The draft changed just before sending.")
            case .permissionDenied: return refuse(.permissionDenied, "Flow isn't allowed to control Mail.")
            case .mailUnavailable: return refuse(.appUnavailable, "Mail didn't respond.")
            case .cancelled: return ExecutionResult(status: .cancelled, userMessage: "Cancelled before sending. Nothing was sent.")
            }
        }
    }

    /// A refusal before anything was dispatched.
    private func refuse(_ code: ExecutionErrorCode, _ message: String) -> ExecutionResult {
        ExecutionResult(status: .failed, error: code, retrySafe: false, userMessage: message)
    }
}
