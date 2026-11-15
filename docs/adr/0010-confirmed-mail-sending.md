# ADR 0010 — Explicitly confirmed Apple Mail sending (T-023C)

**Status:** Proposed · **Date:** 2026-11-15 · **Branch:** `feature/confirmed-mail-sending`

## Context
Spec 02 §3 (CONFIRMING), §6 (EXTERNAL) and §9 (review/send) need a send to:
- happen only after an exact spoken yes,
- be bound to the current recipients, subject, body and version,
- go out at most once, with no claim of delivery.

FlowPlanner already had single-use `Approval`s bound to draft id, version and SHA-256 content hash, a `SendLedger`, and an `awaitingConfirmation` pause. This ADR tightens those and adds the Mail adapter. There is no second confirmation system.

T-023B (Mail draft editing) is being built in parallel, so sending lives in a new module (`FlowMailSend`) plus one executor file. FlowText and FlowMail's drafting code are unchanged.

## Decisions

### 1. Only an explicit yes approves (`ConfirmationReply`, FlowPlanner)
- **Approves:** "yes" / "yeah" / "yep", optionally with "send it", "now", "please" and similar.
- **Declines:** any negation or cancel word ("no", "don't", "never mind", "cancel", "wait", "not yet", "actually"). Flow says the draft is still open.
- **Not an approval; Flow asks again and the confirmation stays open:**
  - vague assent ("sure", "okay", "go ahead");
  - a repeated "send it" / "send that email";
  - Flow's own prompt heard back. It contains "no", so it parses as a decline.
- **Read-back:** "Read the email before sending" repeats the confirmation.
- **Anything else** (e.g. an edit) abandons the confirmation, as before.

### 2. The confirmation names everything and expires
- **What it says:** recipients, subject and the verified body. Any quoted original is mentioned but not read aloud.
- **Expiry:** `ApprovalRequest.askedAt` with `Approval.lifetime` (120 s). On the voice path, FlowSpeech also cancels an unanswered confirmation after 45 s.
- **Stopping it:** stop/cancel clears it.

### 3. The live draft is re-read right before asking
- The planner always inserts a review step before `request_send`, even if the draft was reviewed earlier. An earlier review may predate an edit made in Mail or by FlowText.
- The prompt is built from that fresh snapshot.

### 4. The executor re-verifies at send time (`ExecutorSend.swift`)
1. The bound approval must authorize exactly the bound draft: same id, version and hash, unexpired. Otherwise it fails with `approval_invalid`.
2. `MailDraftController.refresh(id, present: true)` re-reads the draft on screen: recipients via scripting, body via Accessibility. Any difference bumps the version.
3. The live snapshot's version and hash must equal the approval's, or it fails with `draft_changed`. A same-title, same-recipient draft with one changed character is still refused.
4. More than one compose window with the subject fails with `draft_already_open`.

### 5. `MailSender` dispatches at most once (FlowMailSend)
1. Exactly one open `outgoing message` with the subject must exist.
2. Its To must equal the approved recipients, with no Cc and no Bcc. Nothing is ever silently added (no reply-all).
3. The draft and the approval are claimed *before* dispatch. A retried executor call, a repeated utterance, or the same approval cannot dispatch again.
4. Only a send that Mail explicitly reported as failed, with the draft still open, may be retried, and only with a new approval.
5. One script call re-checks To/Cc/Bcc and a content digest, then calls Mail's `send` (from Mail's dictionary: `send` takes an outgoing message and returns a boolean). Nothing can change between that check and the send.

### 6. Outcomes are evidence-based
| Outcome | Evidence | Result | Ledger |
|---|---|---|---|
| `accepted(queued: false)` | Matching message in Mail's Sent mailbox | completed, `.sent`: "Mail sent it… I can't confirm delivery." | sent |
| `accepted(queued: true)` | Still in the Outbox | completed, "still in the Outbox" | sent |
| `notSent` | Mail returned false and the draft is still open | failed `not_sent` | cleared (a new approval may retry) |
| `unknown` | Script error/timeout after dispatch, or the window closed with nothing in Sent or Outbox | unverified, "couldn't confirm… check Sent" | unverified: blocks further sends of that draft |
| `refused` | Nothing dispatched | failed (`approval_invalid`, `draft_changed`, `recipient_mismatch`, `draft_already_open`, …) | cleared |
| `rehearsed` | Dry run | completed, `.sendRehearsed` | rehearsed: blocks repeats |

A closed compose window is never treated as evidence of sending, and Mail accepting a message is never reported as delivery.

### 7. Modes
- `MailSendMode` is **disabled by default**: no sender, or `.disabled`, means `request_send` is unsupported.
- `.dryRun` runs every check against the real draft, then records a `DryRunRecord` instead of calling `send`.
- `.live` also requires a recipient allowlist in Flow.app.

Flow.app settings:
- `FLOW_SEND_MODE=dry-run`
- `FLOW_SEND_MODE=live` with `FLOW_SEND_ALLOWED_RECIPIENTS=a@x,b@y`. Without the allowlist, sending stays off.

### 8. The model can't send
- A model `request_send` needs "send" in the spoken words (existing guard).
- Even then it only *starts* the review → confirm flow. Only `ConfirmationReply.approve` creates an `Approval`.
- "Send my reply to Priya" is refused when the open draft is to someone else.

## Shared contract changes (FlowPlanner / FlowRouting)
- `ApprovalRequest.askedAt` (init with default)
- `ConfirmationReply`, `SendWording`
- `SendLedger.Outcome.rehearsed`
- `Observation.sendRehearsed(draftID:)`
- `ExecutionErrorCode.notSent`
- `PlanRunner.refusedBeforeSending`
- `TaskPlanner`: the review is always re-run before send
- `Rules.send` broadened ("send that email/reply"), plus `sendNamed` with a recipient check
- `MacPlanExecutor.init(…, sender:)`; `ExecutorEngine.sender`

## T-023B integration (after `feature/mail-draft-editing` merges)
1. **Edits must surface as a new version.** An edited draft must reach the planner as `Observation.draft(snapshot)` with a higher `version`. `PlanRunner.apply` then invalidates any approval. Sending relies only on `version` + `contentHash`, never on window title, subject or recipient alone.
2. **Keep `MailDraftController` semantics, or provide equivalents:**
   - `state(id)` returns the registered draft;
   - `refresh(id, present:)` re-reads the live window, bumps `version` on *any* difference, and returns `.draftAmbiguous(n)` for more than one window and `.draftGone` when it closes.

   `ExecutorSend.swift` uses only these two calls.
3. **Subject edits.** Drafts are located by subject (FlowMail and the send script). If T-023B allows editing the subject, the registry must follow the new subject before send can find the draft. Otherwise send refuses with "no longer open", which is safe.
4. **Editing during a confirmation.** An edit spoken while a confirmation is open abandons it (`TaskSession`). The next "send it" re-reviews and asks again.
5. **Expected merge conflicts** are tiny:
   - `MacPlanExecutor.swift`: the `case .insertText, .replaceText` line sits next to `case .requestSend`.
   - `Package.swift`: the FlowExecutor dependencies line.

## Consequences
- Real sending is implemented but **not verified live**. It needs an explicitly approved test to an address the user controls.
- After a send, "send it again" finds no draft. After an unknown outcome, it is refused until the user checks Sent.
