# ADR 0007 — Voice-session coordinator and real plan executor

**Status:** Proposed · **Date:** 2026-11-14 · **Branch:** `feature/voice-executor-integration`

## Context
Voice (FlowAudio/FlowArgmax), routing (FlowRouting), planning (FlowPlanner) and execution (FlowWindow, FlowAX, FlowMail) were built separately:
- ADR 0002 defines `VoicePipeline` → `IntentSink`.
- ADR 0004 makes the router's `ConversationContext` the task-context store, updated by the executor.
- ADR 0005 defines `PlanExecuting` and `TaskSession`.

Nothing yet connected a spoken utterance to a verified action. This ADR derives the connecting pieces from those contracts. It introduces no new task state and no new routing.

## Decision 1 — `VoiceSessionCoordinator` (module `FlowSession`)
```swift
public actor VoiceSessionCoordinator: IntentSink {
    init(session: TaskSession, transcriber: (any SpeechTranscribing)?, permission: (any MicrophonePermissionProviding)?,
         policy: EndpointPolicy = .init())
    nonisolated let events: AsyncStream<CoordinatorEvent>   // .status, .finalized, .incomplete, .turn
    var status: CoordinatorStatus                            // listen: ListenStatus, task: TaskPhase
    var turns: [SessionTurn]                                 // evidence log (no message bodies)
    func startListening() async
    func stopListening() async
    func submit(_ text: String) async -> SessionTurn?       // typed input, same path as voice
    func deliver(_ routed: RoutedUtterance) async           // IntentSink, called by VoicePipeline
}
```
Rules, each traced to an existing contract:

| Rule | Source |
|---|---|
| Only finalized, ASR-confirmed text is handled; hypotheses are display-only (`ListenStatus.hearing`) | spec 02 §3; ADR 0002 |
| **Routing happens once, in `TaskSession`.** The pipeline gets a `PassThroughClassifier`, because `IntentRouter.route` mutates the context and routing twice would corrupt it | ADR 0004 (single store) |
| **No coordinator task state.** Task state is the router's `ConversationContext` plus `PlanRunner`'s run state. The coordinator keeps only HUD status and a turn log | ADR 0004/0005; user requirement |
| Commands run **one at a time, in spoken order** (serial queue) | ADR 0002 |
| **stop/cancel bypass the queue.** They call `TaskSession.handle` immediately, which runs `PlanRunner.cancel()`, cancels the in-flight executor task, and drops queued commands; the pipeline also clears the router's open question | spec 02 §3 global invariants |
| HUD status: `ListenStatus` from `PipelineEvent`, `TaskPhase` from `SessionReply`/`RunState` (`awaitingChoice` shows the numbered options; `awaitingAnswer` when the router's pending question in the shared context is open) | spec 02 §3 states |

## Decision 2 — `MacPlanExecutor: PlanExecuting` (module `FlowExecutor`)
Implements ADR 0005's routing table with Track A modules. Every target is revalidated by the module that acts on it.

| Action | Route | Observation |
|---|---|---|
| `activate_app` | FlowWindow `.activate`, which verifies frontmost and a window | `.appActive(app)` |
| `move/resize/tile_window` | FlowWindow (verified re-read, undo) | `.window(SelectedWindow)` |
| `click_element`, `focus`, `scroll` | FlowAX `UINavigator` | `.uiActed(label)` / `.scrolled`; ambiguity → `needs_clarification` |
| `read_message` (mail) | FlowMail: verbatim query → `MailQuery` | 1 match → open → `.messageOpened`; >1 → `.messageCandidates` with a new epoch; bound choice → open exactly that ref; older epoch or changed message → `failed/.staleTarget` |
| `create_draft`, `insert/replace_text`, `request_review` | **not enabled** | `unsupported` (nothing changed) |
| `request_send` | **disabled** | `unsupported` "Nothing was sent." The runner treats this as "nothing sent" |
| `query_calendar` | not built (T-024) | `unsupported` |

Safety additions:
- **Mail test-mode scope (`ExecutorConfiguration.mailScope = .testMailbox("FlowTest")`, the default).** Every search is forced into that mailbox, a spoken mailbox name other than it is refused, and message references outside it are refused, so real mailboxes are never searched or opened, whatever is said.
- **FlowAX refuses Send/Delete/Discard/Trash/Erase-labelled controls** in generic clicks (`refuseConsequentialControls`, default on), per ADR 0004's defence-in-depth request.
- **Cancellation:** checked before acting; returns `.cancelled`. Committed effects are reported, as ADR 0005 requires.
- `MessageRef.id` is a deterministic (sorted-keys JSON, base64) encoding of FlowMail's `MailMessageRef`. The runner compares ids, so encoding must be stable.

## Decision 3 — Flow.app wiring
- The **"Voice" tab** shows: Start/Stop listening; listen status and interim words; the last finalized utterance; Flow's replies; numbered choices while a plan waits; typed input into the same coordinator; and a turn log. The "Mail: FlowTest only (test mode)" scope is shown permanently.
- **Composition:** `ArgmaxTranscriber` (when the SDK is linked) + `SystemMicrophonePermission` → coordinator → `TaskSession(IntentRouter(Bonsai via LM Studio))` → `MacPlanExecutor(WindowController, UINavigator, MailController)`.
- **Argmax key:** read from `ARGMAX_API_KEY` if set, otherwise from the user's login Keychain (service `dev.flow.FlowApp`, account `ARGMAX_API_KEY`), saved from the Voice tab. Never in source, logs or the repo.
- **Info.plist:** `NSMicrophoneUsageDescription` (ADR 0002 §3).

## Planner changes made with this integration (FlowPlanner, found in the live voice test)
- Filler-only clauses ("Um" in "Um, open notes") are dropped before routing (`TaskPlanner.isFillerOnly`).
- A partial answer to a choice that matches a strict subset of candidates narrows the question to that subset (`PlanRunner.narrow`).

## Consequences
- The executor answers ADR 0005 Q2 (Mail identity and epochs, see ADR 0006) and Q3: the verbatim query is parsed deterministically, and the structured-filter proposal stands.
- Still open from ADR 0005: generic choice observation (§4); FlowAX numbered choices can't yet resume a plan. Drafting, review and send wait for T-023 and an explicit decision to enable them.
- ADR 0005 Q5: the coordinator returns `say` text for the HUD; spoken output (TTS) isn't wired yet.
