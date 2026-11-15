# ADR 0005 — Planner ↔ executor contract (Track B → Track A)

**Status:** Proposed (needs Track A agreement) · **Date:** 2026-11-14 · **Owner:** Track B (`feature/task-planner`)

## Context
`FlowPlanner` turns validated intents into bounded plans (≤5 steps, allowlisted `FlowAction`s only) and runs them through one protocol, `PlanExecuting`. It never touches macOS. Track A owns real execution (FlowWindow, FlowAX, Mail and future channel adapters, Calendar). The planner is **channel-agnostic**: messaging steps carry a `MessageChannel` (`mail`, `messages`, `whatsapp`, or any string), and channel specifics live only in `ChannelCatalog`.

**This branch makes no FlowCore changes.** New shared-looking types live in FlowRouting/FlowPlanner (Track B) until Track A agrees to promote them.

## The contract Track A implements

```swift
public protocol PlanExecuting: Sendable {
    func execute(_ request: ExecutionRequest) async -> ExecutionResult
}
// ExecutionRequest: planID, stepID, attempt, action: FlowAction, channel: MessageChannel?,
//                   bindings (message: MessageRef?, draft: DraftSnapshot?, approval: Approval?), expectation
// ExecutionResult:  status, observation, error: ExecutionErrorCode?, retrySafe, userMessage
```

| Capability (`FlowAction`) | Route to | Must observe and return |
|---|---|---|
| `activate_app` | FlowWindow | `.appActive(app)` after verifying frontmost |
| `move/resize/tile_window` | FlowWindow | `.window(SelectedWindow)` from the post-action re-read |
| `click_element`, `focus` | FlowAX `NavCommand(FlowAction)` | `.uiActed(label:)` |
| `scroll` | FlowAX | `.scrolled` |
| `read_message` | channel adapter (`request.channel`) | 1 match → `.messageOpened(m)`; >1 → `needs_clarification` + `.messageCandidates([…])`; with `bindings.message` → open **exactly** that one or `failed/.staleTarget` if its `epoch` is stale |
| `create_draft` | channel adapter | `.draft(DraftSnapshot)` **as visible in the compose UI**. With `bindings.message`: a reply in that thread to its sender only (no silent reply-all), `inReplyTo = message.id` |
| `insert_text`, `replace_text` with `bindings.draft` | channel adapter | `.draft(updated)` with **version + 1**; `failed/.draftChanged` if the live draft version ≠ bound version |
| `request_review` | channel adapter / HUD | `.reviewShown(liveDraft)` after the draft is visibly presented |
| `request_send` | channel adapter | see below |
| `query_calendar` | Calendar (EventKit) | `.lookupResult(answer:)` |

### Send (non-negotiable)
1. Re-read the **live** draft and check `bindings.approval.authorizes(.send, on: live, now:)`. That means the same draft ID, version and SHA-256 over channel + normalized recipients + subject + body, and not expired. If the check fails, return `failed/.approvalInvalid` and **do not send**.
2. Send once. Return `completed/.sent(draftID:queued:)` only when the channel shows a sent or queued state. If the outcome is unknown, return `unverified` (or `failed/.timeout`). **Never retry a send internally.** The planner records unknown outcomes and refuses further sends of that draft.
3. `failed` with `.approvalInvalid`/`.draftChanged`, or `unsupported`, asserts that **nothing was sent**. The planner then allows a later, freshly reviewed send.

### General rules
- **Revalidate every target against live state** (Track A already does this for windows and AX).
- `retrySafe = true` only if repeating the identical request cannot duplicate an effect. The planner retries at most once, and only low-risk steps.
- **Honor `Task` cancellation** at safe checkpoints and return `.cancelled`. Report effects that were already committed.
- **Status values mirror** `ActionStatus` / `NavigationStatus`: `completed, partially_completed, failed, unsupported, unverified, needs_clarification`, plus `cancelled`. Only `completed` with a matching observation advances the plan.
- **Any draft change Flow didn't make** (the user typing in the compose window) must bump `DraftSnapshot.version`. That is how approvals are invalidated.

## Proposed FlowCore changes (for Track A review)
1. **Promote the shared execution contract** to FlowCore: `ExecutionStatus` (unifying ADR 0001 §1 and ADR 0003 §1, including `needs_clarification`), `ExecutionResult`/`Observation`, `MessageRef`, `DraftSnapshot`, `Approval`, `SelectedWindow`, and the verified half of `ConversationContext` as plan 03's `TaskContext` (supersedes ADR 0004 §1).
2. **Channel on messaging actions.** Either add `channel: MessageChannel?` to `read_message` / `create_draft` / `request_review` / `request_send`, or keep it on the request as now. The model schema should still not emit channel freely; it comes from deterministic resolution.
3. **Allowlisted apps for new channels.** `KnownApp` has no Messages or WhatsApp. Either add them (Messages is first-party; WhatsApp is third-party and needs a policy decision), or let channel adapters prepare their own app (the current planner behavior when `ChannelInfo.app == nil`).
4. **A generic choice observation.** FlowAX's numbered `Clarification` and the planner's message candidates should share one `needs_clarification` + options shape, so a plan can pause on *any* ambiguous target and resume with the chosen element (today it pauses only for messages and stops for other ambiguities).
5. **Delete stays absent** from `FlowAction` (PRD allows declining it). `ConsequentialAction.delete` exists in the approval type so it can be added later without a new mechanism.

## Open interface questions
1. **Drafts in chat channels.** Messages and WhatsApp have no draft ID. Proposal: the adapter treats the conversation's compose field as the draft (`id` = conversation ID), bumps `version` on any change, and "review" means showing the composed text unsent.
2. **Message identity and epochs in Mail.** What stable ID does the Mail adapter use (Message-ID header, AppleScript id), and when does a result set's epoch change?
3. **Search input.** The planner passes the spoken query verbatim ("Sarah's email about tomorrow"). Should it pass structured filters (sender, topic, date) instead?
4. **Review surface.** Native compose window or HUD? Either way, `.reviewShown` must reflect what the user actually saw.
5. **Who speaks confirmations?** The planner produces the prompt text; TTS and HUD are Track A (spec 02 §2 `HUDAndSpeech`).
6. **Send-ledger persistence.** The ledger is in memory. Should an unknown-outcome send survive an app restart?
7. **Approval lifetime** is 120 s. Is that acceptable for slow speakers?
