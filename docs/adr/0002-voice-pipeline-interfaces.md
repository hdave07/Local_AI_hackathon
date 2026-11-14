# ADR 0002 — Voice pipeline interfaces (Track B → Track A)

**Status:** Proposed · **Date:** 2026-11-14 · **Author:** Track B (`feature/voice-ai`)

## Context
Track B delivers finalized utterances and validated intents. Track A owns the app, executor and Info.plist. Plan 03 §7 requires interface changes to go through an ADR.

## Decisions requested

1. **`FlowCore.Utterance` (added, additive).** New file `Sources/FlowCore/Utterance.swift` with exactly the plan 03 §3 fields `(id, stableText, language, timestamp, sessionID)`. No existing FlowCore type was modified. *Please confirm or ask for changes before merge.*

2. **Move the intent hand-off to FlowCore (proposal, not done).** `IntentSink` and `RoutedUtterance` currently live in `FlowAudio`. If Track A's executor should implement the sink without importing `FlowAudio`, move them to FlowCore unchanged:
   ```swift
   public protocol IntentSink: Sendable { func deliver(_ routed: RoutedUtterance) async }
   public struct RoutedUtterance: Sendable, Equatable {
       utterance: Utterance; outcome: Result<Intent, ClassificationError>
       routedBy: RouteSource /* .deterministic | .model */; routingLatency: Duration
   }
   ```
   Contract: delivered intents are *proposals*. `kind == .control` (stop/cancel/stop dictation) arrives ahead of queued commands; a cancelled command arrives as `.failure(.cancelled)` and must not execute.

3. **Info.plist (Track A).** Add `NSMicrophoneUsageDescription` to `Resources/Info.plist` before the packaged app captures audio. The terminal harness does not need it.

4. **App wiring (Track A, when ready).** Composition root:
   `VoicePipeline(transcriber: ArgmaxTranscriber(settings: .fromEnvironment()), permission: SystemMicrophonePermission(), classifier: BonsaiIntentClassifier(...), sink: <executor>)`, observe `pipeline.events` for HUD states (`listening`, `hearing(partial)`, `routing`, `failed(AudioError)`), and show `AudioError.userMessage`.

## Consequences
- FlowAudio stays SDK-free and testable. Argmax lives only in `FlowArgmax`, which is optional at build time (`FLOW_DISABLE_ARGMAX=1`).
- No Track A module was modified by Track B.

## Compatibility with ADR 0001 (Track A, window action results) — reviewed at merge

| Check | Result |
|---|---|
| FlowCore edits on either branch | Track A: none. Track B: one additive file (`Utterance.swift`). No existing type changed. **No breaking change.** |
| FlowWindow's use of FlowCore (`KnownApp`, `WindowTarget`, `WindowPosition`, `ResizeChange`, `FlowAction`) | Unchanged by Track B; `WindowCommand(FlowAction)` still compiles and its tests pass after the merge. |
| 0001 §1 promote `ActionStatus`/`ActionResult` | Compatible: independent of `IntentSink`/`RoutedUtterance` (intent hand-off vs. execution result). |
| 0001 §2 add `minimize_window`/`restore_window` | Track B agrees. **Source-breaking for exhaustive switches**: `FlowAction.type/risk/targetDescription`, `IntentValidator.buildAction`, `flow-bench` `ActionSignature`, plus prompt and benchmark fixtures. Land as one coordinated change and re-run T-002. |
| 0001 §3 titled `WindowTarget` case | Same exhaustive-switch impact (`IntentValidator.windowTarget`, `flow-bench` `WindowTarget.signature`, FlowWindow). Coordinate as above. |
| 0001 §4 `AppWindowRef` epoch | No Track B dependency. |

Status of this ADR's own proposals is unchanged: §1 needs Track A sign-off, and §2–§4 are not implemented. In particular, FlowApp is **not** wired to the voice pipeline, and model output is **not** connected to FlowWindow execution.
