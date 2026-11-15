# ADR 0008 — Spoken feedback for voice sessions (T-014 / T-012)

**Status:** Proposed (hook needs review) · **Date:** 2026-11-14 · **Branch:** `feature/spoken-feedback` · **Owner:** Track B

## Context
The Voice tab shows Flow's replies but does not speak them (ADR 0007, open ADR 0005 Q5). Track A is building Calendar on another branch. To avoid merge conflicts, this work must not edit `FlowApp.swift`, the Voice tab, FlowCore, planner types or the real executor. It lives in a new module and uses the existing voice-session interface.

## Decision 1 — module `FlowSpeech` (new, Track B)
| Type | Role |
|---|---|
| `SpeechOutput` / `SystemSpeechOutput` | Local TTS via `AVSpeechSynthesizer` (on-device voices). Falls back to any installed voice. With no voice: `.unavailable`, and Flow stays visual-only. `stop()` resolves pending speech as `.interrupted` itself, because live testing showed macOS may report `didFinish` for a stopped utterance. |
| `FeedbackPolicy` | Pure decision: **always speak** questions ("Which Sarah? Sarah Chen, Meeting tomorrow; or Sarah Okafor, Lunch tomorrow?"), send confirmations (recipient and body), failures and microphone loss. **Speak** informational outcomes (draft shown, sent, declined, lookup answers). **Silent** for routine low-risk successes. Verbosity: `minimal` / `normal` / `verbose`. Bracketed tags like "[FlowTest]" are not read aloud. Prompts never contain a bare control word. |
| `EchoGuard` | Half-duplex echo suppression (no acoustic echo cancellation): speech that started while Flow was talking is dropped, except stop/cancel. A plain "stop" is ignored if Flow's own sentence contains it; "Flow, stop" always works. Speech that began after Flow went quiet is accepted even if it repeats Flow's words. Without recognizer timing, a word-overlap test applies within a tail window. |
| `SpokenFeedback` (actor) | Attaches to a coordinator, gates spoken input through `EchoGuard`, speaks policy cues (newer replaces older), and runs timers: one reminder for an unanswered question; an unanswered **send confirmation is cancelled** (never sent); idle listening stops with a spoken notice. It acts on the session only via the coordinator's public API (`submit("cancel")`, `stopListening()`). |

## Decision 2 — a minimal hook on `VoiceSessionCoordinator` (FlowSession) — **needs review**
```swift
public protocol VoiceSessionHook: AnyObject, Sendable {
    func admit(_ utterance: String, heardFrom: Date?, finalizedAt: Date) async -> Bool  // spoken input only
    func observe(_ event: CoordinatorEvent)                                            // every event, non-blocking
}
extension VoiceSessionCoordinator { public func setHook(_ hook: (any VoiceSessionHook)?) }
```
- **Why a hook, not a second event consumer:** `events` is an `AsyncStream` with one consumer (the Voice tab). A second iterator would take events away from it. The echo guard also has to decide **before** an utterance is handled.
- **Backward-compatible:** no hook means behavior is identical (all existing FlowSession tests pass unchanged). No new `CoordinatorEvent` cases, so exhaustive switches in Flow.app keep compiling.
- **Safety unchanged:** routing, planning, approvals and stop/cancel semantics are untouched. A dropped utterance runs nothing. stop/cancel still bypass the queue.
- `heardFrom` is best-effort. It is set from the first interim words, which arrive through an asynchronous forwarder. The guard falls back to a word-count estimate when it is missing.

## Decision 3 — Flow.app integration (apply **after** Calendar merges; small, reviewed)
In the composition root, after the coordinator is created:
```swift
let feedback = SpokenFeedback(output: SystemSpeechOutput())
Task { await feedback.attach(to: coordinator) }
```
Optional Voice-tab additions: show `feedback.events` / `FeedbackStatus` (speaking, unavailable, muted), a "Stop speaking" button (`stopSpeaking()`) and a mute toggle (`setMuted`). Add `"FlowSpeech"` to Flow.app's dependencies in `Package.swift`. Then run the combined suite.

## Open questions
1. **Barge-in.** Users can only interrupt with stop/cancel while Flow talks; other answers given mid-prompt are dropped (HUD shows `.ignored`). Acoustic echo cancellation (`AVAudioEngine` voice processing on the Argmax input) would allow full barge-in but needs testing with Argmax capture.
2. **Timer defaults:** 20 s reminder, 45 s confirmation expiry, 5 min idle listening. Are these right for slower speakers? They should become user preferences.
3. **Voice and rate selection UI** (System voices; Personal Voice is not used).
4. **Calendar answers** will be spoken automatically if the executor returns them as runner `say` lines (`.lookupResult`); no Calendar-specific code is needed here.
