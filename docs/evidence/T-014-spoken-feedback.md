# T-014 / T-012 evidence — Spoken feedback and voice-session accessibility

**Date:** 2026-11-14 · **Branch:** `feature/spoken-feedback` (uncommitted) · **Base:** `main` @ 3d82d4a · Design: ADR 0008
All tests use `MockExecutor`. Nothing is sent and no destructive action runs.

## Changed files (merge-conflict footprint)
| File | Change |
|---|---|
| `Sources/FlowSpeech/*` (new) | `SpeechOutput`/`SystemSpeechOutput`, `FeedbackPolicy`, `EchoGuard`, `SpokenFeedback` |
| `Tests/FlowSpeechTests/*` (new) | 27 unit/integration tests + 3 opt-in live speech tests |
| `Sources/FlowSession/VoiceSessionCoordinator.swift` | +34/−2: optional `VoiceSessionHook` (`admit`, `observe`), `setHook`, first-words timestamp |
| `Package.swift` | +7: `FlowSpeech` target, product and test target |
| `FlowApp.swift`, Voice tab, FlowCore, FlowPlanner, FlowExecutor, Calendar | **untouched** (Flow.app wiring is deferred to after the Calendar merge; ADR 0008 §3) |

## Acceptance
| Criterion | Evidence |
|---|---|
| Flow speaks "Which Sarah?" when several messages match | `whichSarahIsSpokenAndAnsweredByVoice`: spoken text starts "Which Sarah?", names both Sarahs, and omits "[FlowTest]" |
| The user answers by voice and the task continues | Same test: the spoken "Sarah Chen" resumes the plan → reply drafted → "Here's the draft…" spoken; nothing sent |
| Important failures are announced | `importantFailuresAreAnnounced` (executor failure spoken, kind `failure`); `microphoneFailureIsAnnounced` |
| Flow can be interrupted safely | `flowStopInterruptsSpeechAndTheTask` (speech cut **and** plan cancelled); `typedStopAlsoStopsSpeech`; `newerFeedbackReplacesOlderSpeech`; live `speaksAndCanBeInterrupted` |
| Complete suite passes | **485 tests** (482 run + 3 opt-in live, skipped by default) |

## Requirements → tests
| # | Requirement | Tests |
|---|---|---|
| 1 | Local TTS (AVSpeechSynthesizer) | `SystemSpeechOutput`; live `aVoiceIsAvailable` (voice "Samantha"), `speaksAndCanBeInterrupted` ("Which Sarah?" spoken in ~1.0 s) |
| 2 | Speak clarifications, confirmations, failures, concise outcomes | acceptance tests; `confirmationIsSpokenWithRecipientAndContentAndNoSendsNothing`; policy suite |
| 3 | No narration of routine low-risk actions | `routineLowRiskSuccessIsNotNarrated`, `silentRoutineVerboseDone`, `minimalKeepsOnlyQuestionsConfirmationsAndFailures` |
| 4 | Visual feedback preserved | Voice tab untouched; `unavailableVoiceDegradesToVisualOnly` checks the on-screen question remains |
| 5 | Flow's speech is never a command | `ownPromptHeardWhileSpeakingIsDropped`, `otherSpeechDuringFlowsSentenceIsDroppedHalfDuplex`, `echoArrivingJustAfterSpeechWithoutTimingIsDropped`, `answerStartedAfterFlowFinishedIsAcceptedEvenIfItRepeatsFlowsWords` |
| 6 | Interrupt speech, including "Flow, stop" | `flowStopInterruptsSpeechAndTheTask`, `plainStopInsideFlowsOwnSentenceIsIgnoredButFlowStopWorks`, `typedStopAlsoStopsSpeech` |
| 7 | Listening states, timeouts, interruptions | `FeedbackStatus` (ready/speaking/unavailable/muted); `unansweredConfirmationIsRemindedThenCancelledNeverSent`, `unansweredChoiceIsRemindedOnceAndStaysOpen`, `idleListeningTimesOutAndSaysSo` |
| 8 | Deterministic stop/cancel and planner safety preserved | stop/cancel still bypass the queue; existing FlowSession/FlowPlanner suites unchanged and passing; timeout cancels, never sends |
| 9 | Unavailable voices, microphone interruptions | `unavailableVoiceDegradesToVisualOnly`, live `missingRequestedVoiceFallsBack`, `microphoneFailureIsAnnounced` |
| 10 | Tests for feedback, interruptions, confirmation dialogue, state transitions | 27 tests in `Tests/FlowSpeechTests` (5 runs, all passed) |
| 11 | Mock executor; no sends or destructive actions | All integration tests use `MockExecutor`; send assertions check `sendRequests.isEmpty` |
| 12 | Modular for the Calendar merge | New module + opt-in hook; `detachRestoresTheUnhookedCoordinator` |

## Bug found by the live test (fixed)
Stopping `AVSpeechSynthesizer` mid-sentence stopped the audio, but the result came back as **finished**, not interrupted; macOS reported `didFinish`. The mock had hidden this. `SystemSpeechOutput.stop()` now resolves pending speech as `.interrupted` itself and ignores late callbacks.

## Limitations
1. **Not yet in Flow.app.** The integration lines are in ADR 0008 §3, to apply after the Calendar merge. Until then spoken feedback is exercised by tests only.
2. **Half-duplex:** answers spoken *over* Flow's prompt are dropped (only stop/cancel interrupt). Real echo cancellation is an open question (ADR 0008 Q1).
3. **Echo timing is best-effort.** The coordinator's first-words timestamp can lag. The fallback estimate assumes ~0.35 s per word plus a 1 s endpoint, and very fast or very slow speakers may be mis-timed. The defaults were not tuned with real users, and Flow's speech playing into the live Argmax microphone was not tested end to end.
4. **Timer defaults** (20 s / 45 s / 5 min) are not user-configurable in the UI yet.
5. **English phrasing only.**
