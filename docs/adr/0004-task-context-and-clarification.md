# ADR 0004 — Task context and clarification hand-off (Track B → Track A)

**Status:** Proposed (needs Track A agreement) · **Date:** 2026-11-14 · **Owner:** Track B (`feature/voice-improvements`)

## Context
`feature/voice-improvements` adds `FlowRouting`. It handles stop/cancel, a deterministic fast path, reference resolution ("it", "that window", "her"), clarification, and Bonsai with slot grounding. To resolve references it needs task state. Plan 03 §3 lists `TaskContext(activeWindow, selectedMessage, draftID, draftVersion, previousTarget, pendingQuestion)` as a shared FlowCore contract, but it does not exist yet. Its real source of truth is the executor (Track A): only Track A knows what actually opened, focused or was sent.

**This branch makes no FlowCore changes.** Everything below lives in `FlowRouting` until Track A agrees.

## What exists now (Track B-local)
| Type | Purpose |
|---|---|
| `ConversationContext` | `activeApp`, `recentPeople` (≤3, most recent first), `openMessage`, `hasDraft`, `lastEditedText`, `pending`, `updatedAt` (ignored after a 10 min TTL) |
| `PendingQuestion` | open clarification: `.app(then:)`, `.person(candidates:then:)`, `.position(window:)`, `.textToReplace(replacement:)` |
| `IntentRouter` (actor, `IntentClassifying`) | records the intents it *proposes*; `updateContext(_:)` lets the executor replace that with verified state; `cancelPendingQuestion()` |
| Clarifications | `Intent(kind: .clarification, action: nil, summary: <question>, source: .deterministic)`. The question text lists the voice options. |

Proposed-intent context is an approximation: if the executor fails to open Notes, "open it" still means Notes. The TTL and the uniqueness rule (exactly one candidate, else ask) limit the damage. Executor-verified context removes the gap.

## Proposals

1. **Promote a `TaskContext` to FlowCore** with the fields above plus Track A's identity fields (`AppWindowRef`/`WindowRef`, message ID, draft ID and version, per ADR 0001 §4 and plan 03 §3). Track A's executor *writes* it after verified actions; Track B's router *reads* it. Pure value type, `Sendable`, `Equatable`.
2. **Executor → router update path:** after each `WindowActionResult`/mail result with status `completed`, Track A calls `IntentRouter.updateContext(_:)`. `failed`/`unverified` results leave references unresolved, so the router asks.
3. **Structured clarification (optional):** add `options: [String]` to clarifications, either as a new `Intent` field with a default (source-compatible) or as a FlowCore `Clarification` type. The HUD could then show numbered, speakable choices. Today the options are only in the question text, and the answer is parsed by `PendingQuestion` in the router.
4. **No change to `FlowAction`, `IntentKind` or `IntentSource`.** Deterministic routes use the existing `IntentSource.deterministic`.

## Compatibility
- Additive only. The ADR 0001 proposals (new minimize/restore actions, titled `WindowTarget`) remain compatible. When they land, `Rules`/`Guard` in FlowRouting gain cases in the same coordinated change.
- FlowWindow is not imported by FlowRouting, and FlowRouting executes nothing.

## Response to Track A ADR 0003 (UI navigation), verified against `main` @ 5a4f285

Verification: this branch's changes were applied to `main` in a scratch worktree, with no merge or commit. It builds, and all 270 tests pass: this branch's 211 (including FlowWindow 48) plus FlowAX 59. A temporary cross-track test fed router output through `NavCommand(FlowAction)`: "click the second Reply button" → words `[reply]`, role `.button`, ordinal 2; "focus the search field" → role `.textField`; "scroll down" → `.scroll(nil, .down, .frontmost)`.

| Track A 0003 item | Track B position | Done on this branch |
|---|---|---|
| §1 `ActionStatus` with `needs_clarification` | **Agree.** Router clarifications (intent level, before execution) and FlowAX `needs_clarification` (result level, after inspection) are complementary. Both should reach the HUD as one voice-answerable question. | — |
| §2 numbered-choice / overlay commands deterministic | **Agree they must not reach the model.** Prefer **new `FlowAction` cases** (`showNumbers(String?)`, `hideNumbers`, `chooseNumber(Int)`) over `ControlCommand`: choosing a number presses something, so it needs risk/confirmation handling, unlike stop/cancel. These cases must be **excluded from the model schema** (`IntentSchema.allowedActionNames` currently derives from `ActionType.allCases`, so add a `modelEmittable` filter in the same change). | Router recognizes "show/hide numbers", "choose/pick/number N" and bare "N" deterministically (stage `overlay`). Until the FlowCore cases exist it declines them rather than guess. An answer to a pending router question takes precedence over a bare number. |
| §3 raw `click_element`/`focus` labels | **Agree.** | Fast path now passes the spoken reference unchanged (articles, ordinals, role words). |
| §4 app scope on navigation actions | **Agree (optional).** "click Save in Notes" currently yields label "Save in Notes" in the front app; FlowAX's resolver should then return not-found / clarification. | — |
| *(new, safety)* consequential buttons | **Proposal to Track A:** FlowAX presses whatever it resolves. Add a defense-in-depth check so that a resolved element labelled Send / Delete / Discard / Trash is never pressed by `perform` without the planner's confirmation. | Router never emits `click_element` for send/delete labels: "click send" → `request_send` (review + confirmation); delete/discard/trash → declined. This also applies to model output. |
| ADR numbering | Track A's UI-navigation ADR took 0003; this ADR is renumbered **0004**. | Renamed. |
