# T-023C — Explicitly confirmed Mail sending

Branch `feature/confirmed-mail-sending` (from main `272224a`). Design and safety model: [ADR 0010](../adr/0010-confirmed-mail-sending.md).
**No email was sent during this work.** Real sending is implemented but disabled by default and not verified live.

## What's implemented
- **Routing:**
  - Send requests: "Send that email.", "Send my reply to Sarah." (checked against the draft's recipient), "Can you send it?"
  - Answers while a confirmation is open: "Yes, send it.", "No, don't send.", "Cancel.", "Actually, never mind.", "Read the email before sending."
- **Flow:**
  1. Send request.
  2. Live re-read and review of the draft.
  3. Spoken and visual confirmation naming the recipients, subject and full body.
  4. Explicit yes, which creates a single-use approval.
  5. Executor re-reads the draft on screen and matches version and hash.
  6. `MailSender` re-checks Mail's own draft (To exact, no Cc/Bcc, content digest) inside the script that sends.
  7. Exactly one dispatch.
  8. Evidence from Sent or Outbox.
  9. Honest report ("Mail sent it… I can't confirm delivery" / "still in the Outbox" / "couldn't confirm").
- **Modes:**
  - disabled (default);
  - dry-run (`FLOW_SEND_MODE=dry-run`: every check, no Send);
  - live (`FLOW_SEND_MODE=live`, plus `FLOW_SEND_ALLOWED_RECIPIENTS`).

## Tests (all simulated; nothing sent)
| Suite | Tests | Covers |
|---|---|---|
| `FlowMailSendTests` — MailSender | 18 | disabled; Sent vs Outbox vs unknown; error after dispatch = unknown; Mail-reported failure; one dispatch per draft and per approval; unknown never retried; added Cc/Bcc, extra or different To refused; duplicate drafts; last-moment change inside the send script; live allowlist; dry run records once and never calls Send; cancellation; script has a single `Mail.send` and no delete/close/save |
| `FlowExecutorTests` — ConfirmedSendTests | 23 | both acceptance scenarios; vague assent and repeated "send" are not approval (7 phrasings); read-back; decline/cancel (6 phrasings); expiry; edit after the question; one-character edit; edit between approval and dispatch; added Cc/Bcc; duplicate compose windows; unknown outcomes never retried; Mail-reported failure; Outbox; disabled by default; model bypass; "send" inside dictated content; Flow's echoed prompt; wrong named recipient; retried executor call; cross-draft approval; no approval; stop during confirmation |
| `FlowExecutorTests` — VoiceSendTests | 7 | spoken dry run announced; repeated recognizer segments send once; Flow's own prompt heard while speaking is ignored; coordinator timeout cancels; microphone failure during confirmation; spoken "never mind"; unknown outcome announced as uncertain |
| `FlowMailSendTests` — Live (`FLOW_LIVE_MAIL=1`) | 1 | the send script's read-only `outgoing` and `evidence` operations against real Mail, for a subject that can't exist (passed, ~10 s); `send` is never called |
| Full `swift test` | all suites | pass (exit 0); Flow.app builds and signs |

**Mutation checks:**
- Letting "sure/okay/send" approve fails `vagueAssentOrRepeatedSendIsNotApproval`.
- Removing the executor's version/hash re-check fails `editAfterTheQuestionInvalidatesTheApproval` and `sameLookingEditIsStillDetected`.

### Acceptance scenarios
1. "Find Sarah's email." → "The first one." → "Reply saying I can meet at 3:30." → "Send that reply."
   - Flow re-reads the draft and asks: *Ready to send this email to sarah.chen@example.invalid, subject “Re: [FlowTest] Meeting tomorrow”. It says: “I can meet at 3:30”. Say “yes, send it” to send, or “no”.*
   - "Actually, never mind." → *Okay, I won't send it. The draft is still open.*
   - Send calls: 0. A later "Yes, send it." authorizes nothing. ✅
2. Dry run: verified draft → "Send that reply." → confirmation → "Yes, send it."
   - The executor validates the unchanged draft.
   - `dryRunLog` holds exactly one record, matching the draft id, version and hash.
   - Mail's Send is never called.
   - Saying it again adds no record. ✅

## Limitations / still to verify live
- **Real sending is not verified.** It needs an explicitly approved live test: `FLOW_SEND_MODE=live` with an allowlisted address the user controls, on a FlowTest reply.
- **Evidence of acceptance is local.** It means "found in Mail's Sent mailbox / Outbox with the same subject and recipients since the send". That is acceptance by Mail, not delivery.
  - Searching the unified Sent mailbox took ~10 s on this Mac, so the evidence window is 30 s.
  - A slower Mail gives `unknown`, which is safe.
- **Content check before sending.** The send script compares Mail's scripted `content` digest between its own two calls. The body the user approved is the one Accessibility read on screen; the two are not compared to each other.
- **Recipients.** Only To-only drafts can be sent. Drafts with any Cc/Bcc are refused, because `DraftSnapshot` doesn't separate To/Cc/Bcc.
- **The live dry run against a real Mail draft was not run.** No draft was created in Mail for this milestone, and existing drafts were not touched. Next step: a Flow.app dry run with `FLOW_SEND_MODE=dry-run` on a fresh FlowTest reply.

## After merging T-023B (voice draft editing) from main
- **Conflicts resolved** in `MacPlanExecutor.swift`, `PlanRunner.swift` and the test rig. Both features were kept.
- **No duplicate read-back.** The review read-back from T-023B is skipped when that review only precedes a send confirmation, because the confirmation reads the same verified draft.
- **Bug fixed: an edit during a confirmation was lost.** "Actually, change 3:30 to 4" during a send confirmation was parsed as "no" (because of "actually"), so the edit was dropped. Edit instructions now abandon the confirmation and the edit runs.
- **New test:** `voiceEditDuringConfirmationNeedsANewYes`. The old yes sends nothing; the new text is re-reviewed and needs its own yes, then is sent exactly once.
- **Full suite:** passes.
