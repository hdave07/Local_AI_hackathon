# T-026 evidence — Bounded task planner, execution safety, task state (Track B)

**Date:** 2026-11-14 · **Branch:** `feature/task-planner` (uncommitted) · **Base:** `main` @ 996958f
Nothing here executes macOS actions: all execution in this evidence goes through `MockExecutor`.

## What was built

**`FlowPlanner`** (new Track B module, depending on FlowCore, FlowLLM and FlowRouting; no FlowWindow, FlowAX or FlowApp):

| Component | Role |
|---|---|
| `Plan`, `PlanStep` | Typed plan: ≤5 steps, each with an allowlisted `FlowAction`, `dependsOn`, `preconditions`, `expectation`, origin (spoken or implied), channel. **Derived in code:** `capability`, `risk` (FlowCore `RiskLevel`), `requiresConfirmation` (external), `failurePolicy` (low: retry ≤2 attempts; content: stop; external: never retry). |
| `TaskPlanner` | Utterance → conservative clause split → each clause routed by the existing `FlowRouting` core against a *simulated* context → steps with dependencies. Implied steps: activate the channel's allowlisted app; review before any send. |
| `ChannelCatalog` / `ChannelResolver` | The **only** channel-specific code. Mail (allowlisted app), Messages and WhatsApp (adapter-prepared), and any custom channel. Resolves "on WhatsApp", "text Lee …", "send Lee a WhatsApp …", "email Dana …"; a reply stays in the selected message's channel. |
| `PlanExecuting` | Protocol Track A implements (ADR 0005). Requests carry verified bindings (message, draft, approval); results mirror Track A statuses plus an `Observation`. |
| `PlanRunner` | State machine: `running → awaitingChoice / awaitingConfirmation → completed / stopped / cancelled`. Verifies every observation against the expectation before writing task state. Bounded retries; stale results trigger one re-search; ≤12 executor calls per plan. |
| `Approval`, `SendLedger` | Single-use approval bound to channel + draft ID + version + SHA-256(recipients, subject, body), 120 s lifetime. Ledger: at most one send per draft; an unknown outcome blocks further sends and is never retried. |
| `TaskSession` | Per-utterance entry point: stop/cancel first (no model), then the answer to a paused plan, then plan new work. Anything but yes/no while confirming abandons the send. |
| `MockExecutor` | In-memory world (apps, multi-channel messages, drafts, send log) with fault injection, delays, epochs and external draft edits. |

**Task state = one store.** FlowRouting's `ConversationContext` gained verified fields (`selectedMessage`, `draft`, `reviewedDraftVersion`, `selectedWindow`, `PendingQuestion.plan`). The runner writes them only from verified executor results, through the existing `IntentRouter` store. No competing state store.

**FlowRouting additions:**
- `MessageChannel`, `MessageRef`, `DraftSnapshot` (with `contentHash`), `SelectedWindow`.
- Rules for nameless replies to the open message ("draft a reply saying …"; an explicit connector is required, so named replies keep working) and "show it to me" when a draft exists.

**No FlowCore changes.** Proposals are in `docs/adr/0005-planner-executor-contract.md`.

## Acceptance scenario (`flow-plan-demo`, full transcript in `T-026/demo-transcript.txt`)

"Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me."

```
plan[0] Open Mail (implied, risk low)
plan[1] Find “Sarah's email about tomorrow” in Mail [mail] after 0 (risk low)
plan[2] Draft a reply: “I can meet at 3” [mail] after 1 (risk content)
plan[3] Show the draft for review [mail] after 2 (risk low)
  → activate_app, read_message                      → 2 matches: plan pauses
FLOW: I found 2 messages: 1. Sarah Chen — “Meeting tomorrow” …; 2. Sarah Patel — “Tomorrow's lunch” …. Which one?
USER: the first one
  → read_message message=m1, create_draft message=m1, request_review draft=d-1v1
FLOW: Here's the draft. Say “send it” when you're ready.          (0 sends)
USER: send it   → FLOW: Send this by mail to sarah.chen@example.com? “I can meet at 3” Say yes to send, or no.
USER: yes       → request_send approval(draft d-1 v1 hash bbc420d8…)   → Sent. (1 send)
```

Also demonstrated:
- an edit while confirming (approval dropped; v2 reviewed again before a new prompt);
- the **same planner on WhatsApp** (no Mail step; recipient is the handle; "Send this by whatsapp…");
- stop while choosing (nothing executed afterwards).

## Requirements → evidence

| # | Requirement | Tests (`Tests/FlowPlannerTests`, `FlowRoutingTests`) |
|---|---|---|
| 1 | Typed plan with dependencies, preconditions, verification, failure behavior | `fullWorkflow`, `sendInsertsReviewAndConfirmation` |
| 2 | Activation, windows, UI, message find/read, drafting, lookup | `fullWorkflow`, `singleCommandIsAOneStepPlan`, `partialAndUnsupportedStop`, `routerFollowUpStillWorks`; channel suite |
| 3 | Allowlisted actions only | Steps hold FlowCore `FlowAction` only; `declinedActionsExecuteNothing` |
| 4 | Risk and confirmation derived in code | `PlanStep.risk/requiresConfirmation/failurePolicy`; `sendInsertsReviewAndConfirmation` |
| 5 | Confirmation bound to recipient, content, action; changes invalidate | `editWhileConfirmingInvalidatesApprovalAndRequiresNewReview`, `externalEditAfterAskingBlocksTheSend`, `approvalIsSingleUseAndBound`, `approvalIsBoundToTheChannel`, `otherCommandWhileConfirmingDropsTheSend`, `noMeansNotSent` |
| 6 | Task context: app, window, message, draft, pending clarification | `fullWorkflow` (selectedMessage, draft, reviewedDraftVersion), `pendingQuestionIsMirroredInTaskContext` |
| 7 | Pause on ambiguity, resume only when resolved | `fullWorkflow`, `choosingBySenderNameWorks`, `tiedAnswerIsAskedAgainNotGuessed` |
| 8 | Results → continue / retry / clarify / recover / stop | `retrySafeLowRiskStepIsRetriedOnce`, `notRetrySafeStopsImmediately`, `unverifiedObservationStops`, `staleCandidatesAreSearchedAgainNotTrusted` |
| 9 | Bounded retries; never repeat an uncertain external action | `retriesAreBounded`, `contentStepsAreNotRetriedAutomatically`, `unverifiedSendIsNeverRetried`, `sendTimeoutIsTreatedAsUnknown`, `ledgerRefusesSecondSendOfSameDraft` |
| 10 | stop/cancel interrupts queued execution | `stopInterruptsTheRunningStepAndPreventsLaterSteps`, `cancelWhilePausedDropsTheQuestion`, `cancelDuringConfirmationSendsNothing` |
| 11 | Mock executor; nothing wired to macOS | `MockExecutor`; no FlowWindow/FlowAX import in FlowPlanner |
| 12 | Workflows, ambiguity, stale state, cancellation, failures, duplicate send, invalidation | All of the above, plus `oldQuestionIsRefreshed`, `replyWithoutAMessageAsksFirst`, `sendWithoutADraftStops` |
| — | **Channel-agnostic** (added on request) | `textMessageHasNoMailSteps`, `spokenChannelIsResolved` ×4, `whatsappReplyStaysOnWhatsapp`, `customChannelNeedsNoPlannerChange` |

## Test results

- `swift test`: **310 pass** (previous 270; FlowRouting 58 → 62; FlowPlanner 36 new). FlowPlanner ran 3× with identical results, including the timing-based cancellation test.
- Router benchmark after the FlowRouting rule additions: tuned 45/45, held-out 46/46, context 18/18, **0 unsafe** (unchanged from T-030).

## Limitations

1. **Planning-time clarification in multi-clause commands** (e.g. a missing recipient in clause 2) asks the question, but the user must repeat the whole command. Follow-up answers only complete single-clause commands.
2. **Pauses only for message ambiguity.** Other `needs_clarification` results (e.g. FlowAX numbered options) stop the plan with the executor's message, pending ADR 0005 proposal 4.
3. **The send ledger and approvals are in memory** and do not survive a restart.
4. **Channel phrases are English and rule-based.** An unknown channel name falls back to the catalog default (Mail); the confirmation prompt always says which channel.
5. **Clause splitting can truncate dictated content.** A plain "and" inside content never splits ("tell Lee I'll call and send the notes" stays one draft). But **"and then <command verb>" or ", then <command verb>" does**: "tell Lee I'll call and then send the notes" becomes a draft "I'll call" plus a separate "send the notes" step (verified with a probe). This cannot send anything unintentionally, because any send step still needs a reviewed draft and explicit confirmation. Fix options: let the user say "new step", or only split when the right-hand clause routes deterministically.
6. **Not tested against real adapters.** All results come from the mock; integration needs Track A's executor (ADR 0005).
