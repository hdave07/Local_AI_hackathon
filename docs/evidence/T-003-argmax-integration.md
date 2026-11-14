# T-003 / T-012 evidence — Argmax Pro integration (FlowAudio)

**Date:** 2026-11-14 · **Branch:** `feature/voice-ai` · **Machine:** Apple M5 (Mac17,3), 16 GB RAM, macOS 26.6, Swift 6.4.2

## Status

| Item | Status |
|---|---|
| Argmax Pro SDK via authenticated registry | **Verified**: resolves, builds and links |
| SDK version | **3.1.8** (`ArgmaxSDK.sdkVersion`), binary `ArgmaxSDK.xcframework` + `argmax-oss-swift` 1.1.1 |
| License activation | **Verified** live: `tokenCreation → success` |
| Microphone permission + live capture | **Verified** live (terminal-attributed TCC prompt accepted) |
| Streaming transcription, confirmed vs hypothesis | **Verified** live (mic and file) |
| VAD (speech start/end) | **Verified** on file input; live behavior plausible, not separately measured |
| Typed `Utterance` → Bonsai → mock consumer | **Verified** live |
| Deterministic stop/cancel (no LLM) | Unit-tested, including cancellation of an in-flight model call; not yet spoken live |
| **First milestone** (spoken “Open Notes.” → `activate_app → Notes` at mock consumer, nothing executed) | **Passed live on the microphone** |

## Live results

| Run | Transcript | Routed result | Notes |
|---|---|---|---|
| Synthesized file (`say`), 3 s pad | “Open notes” | `activate_app → Notes`, Bonsai 727 ms | first run: model download 19.6 s, load (CoreML compile) 11.2 s |
| File + 6 s silence inside audio | “Open notes” | `activate_app → Notes`, 819 ms | **final 0.37 s after VAD speech-end**, while silence still streaming |
| Microphone, attempt 1 | “Then uncles, I may uh talk and window.” | `unsupported` (nothing proposed) | misrecognition; cause not determined (ambient speech / device / delivery) |
| Microphone, attempt 2 | “Open Notes” | `activate_app → Notes` [risk low], Bonsai 636 ms | warm load 0.15 s; session 4.5 s |

End of speech → validated intent ≈ 0.7 s (VAD release 0.4 s + hold 0.3 s + SDK flush) + Bonsai ≈ 0.6–0.8 s.

## Finding: the SDK does not confirm during continued silence

With `LiveTranscriber` 3.1.8 + `parakeet-v2_476MB`, confirmed text arrived **only when the input stream ended**. During 8 s of in-audio silence, nothing was confirmed in `.voiceTriggered`, `.alwaysOn` or `.batteryOptimized` mode (`.alwaysOn` also hallucinated in silence). On a live mic, commands would therefore never finalize.
**Fix (FlowArgmax + FlowAudio `UtteranceSegmenter`):** capture the microphone once (`audioProcessor.startStreamingRecordingLive`), give each utterance its own `CustomSource` stream, and end that stream after VAD speech-end + 0.3 s hold. The SDK then flushes and confirms. Results are forwarded in segment order, followed by `.endOfSegment`, which finalizes confirmed text immediately. Only SDK-confirmed text is ever routed (spec 02 §3 holds).

## Registry setup (per machine, never commit the token)

```
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token <SECRET_API_TOKEN>
```
Package: `.package(id: "argmaxinc.argmax-sdk-swift", exact: "3.1.8")`, product `Argmax`.
Versions observed in the registry for this account: 1.12.0, 2.2.0, 3.1.8 (latest 3.x). The docs pages mix 1.7.x, 2.0.9 and 3.0.6.
Builds without registry access: `FLOW_DISABLE_ARGMAX=1 swift build` (drops `FlowArgmax`, `flow-voice`, `FlowArgmaxTests`).

## SDK facts verified from the 3.1.8 interface/source (not from docs)

- `LiveTranscriber(whisperKit:)`, `registerStream(streamSource:options:audioCallback:)`, `startTranscription(for:) -> AsyncThrowingStream<LiveResult, Error>`, `stopAndRemoveStream(for:)`. Streams are one-shot; re-register to listen again.
- `LiveResult.confirm(text:seconds:result:)` = stable text; `.hypothesis(text:seconds:result:)` = interim. Confirmed and hypothesis for the same update arrive confirm-first.
- `ArgmaxSource(streamType: .device(DeviceID?))` requests microphone permission itself via `AudioProcessor.requestRecordPermission()` and throws `ArgmaxError.generic("Record permission denied")`. Flow checks consent first (`MicrophoneGate`) so the user gets a typed, actionable error.
- **No standalone VAD event API** in the streaming path. VAD exists as `StreamTranscriptionMode.voiceTriggered(silenceThreshold:maxBufferLength:minProcessInterval:)` (gates processing) and `DecodingOptions(chunkingStrategy: .vad)`. Threshold units are WhisperKit *relative energy* (dB normalized to 0–1, `AudioProcessor.calculateRelativeEnergy`), not RMS. Flow computes speech start/end from that same measure via `audioCallback`.
- `StreamingConfig.endpointAfter` defaults to 2.0 s (internal endpointing). Expect the last words to be confirmed up to ~2 s after speech ends; Flow's `unconfirmedTailTimeout` (4 s) is set above that.
- Model: `parakeet-v2_476MB` from `RepoType.parakeetRepo` (`argmaxinc/parakeetkit-pro`), Argmax's recommended English real-time model; downloaded with `ModelStore().downloadModel(name:repo:token:)`.
- Custom vocabulary: `WhisperKitProConfig(customVocabularyConfig:)` / `setCustomVocabulary`; docs say Parakeet-only and it requires an extra model (`canary-1b-v2_474MB` or `parakeet-tdt_ctc-110m`). **Not wired**; `capabilities.customVocabulary == false`.
- License: `ArgmaxSDK.with(ArgmaxConfig(apiKey:))`; internet needed on first activation and at least every 30 days (docs). Flow sets `keychainPersistence = false` and records `licenseStatusCallback` events.
- SDK sources are marked "Proprietary and confidential. Under NDA": nothing from the SDK is vendored or committed.

## Design (FlowAudio)

```
MicrophoneGate ─▶ SpeechTranscribing (ArgmaxTranscriber) ─▶ TranscriptEvent stream
   ─▶ UtteranceAssembler (partial | final | incomplete)
   ─▶ DeterministicRouter (stop/cancel/stop dictation, no LLM)  ─┐
   ─▶ IntentClassifying (BonsaiIntentClassifier, unchanged)      ├─▶ IntentSink (MockActionConsumer)
```
- Only `final` (fully confirmed, no pending hypothesis) text becomes an `Utterance` and is routed. Hypothesis-only speech is reported `incomplete` and never routed.
- Stop/cancel cancel queued/in-flight classification and are delivered first; embedded phrases (“stop the music”) go to the model.
- Commands are classified serially in spoken order.
- `FlowAudio` has no SDK dependency, so its tests run anywhere.

## Reproduce

```
swift test                                          # all unit tests (no key, no server)
scripts/flow_voice.sh --file /path/to/audio.aiff --once   # file through Argmax
scripts/flow_voice.sh --once                        # microphone; say "Open Notes."
FLOW_LIVE_ARGMAX=1 FLOW_LIVE_LLM=1 swift test --filter LiveArgmax   # needs key; uses `say`
```
`flow-voice` prints partial/final transcripts, the validated intent and `MOCK CONSUMER received (NOT EXECUTED)`. No app is opened.

## Verified results so far

- `swift test`: 103 tests pass (41 pre-existing + 62 new); `FLOW_LIVE_ARGMAX=1 FLOW_LIVE_LLM=1` live Argmax suite: 2/2 pass.
- `flow-voice --file open-notes.aiff --once` with no key: `licenseMissing` in ~1 ms, zero intents delivered, nothing executed.

## Open questions / limitations

- Microphone accuracy needs a quiet-room vs ambient test and input-device logging (attempt 1 misrecognized).
- Speech overlapping the 0.3 s segment cut is untested live; very short pauses inside a sentence could split it.
- Whether `.confirm` text is incremental or cumulative in practice: the assembler handles both; confirm on first live run.
- `ArgmaxConfig.optOut` (telemetry) semantics are undocumented; left at the default pending a team decision.
- Packaged-app microphone use needs `NSMicrophoneUsageDescription` in `Resources/Info.plist` (Track A owns FlowApp/Info.plist).
- Early interrupt on *hypothesis* “stop” (spec 02 §3 exception) is not implemented: stop acts on the finalized utterance (~0.7 s after speech ends).
