# ADR-001 — Voice pipeline interfaces (Track B → Track A)

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
