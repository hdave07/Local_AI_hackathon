# Flow — Hands-Free Mac

Flow is an offline, voice-first macOS accessibility application designed for people with limited upper-limb mobility who retain reliable speech.

It combines:
- Argmax Pro for speech recognition
- Bonsai 2 (2B/4B/9B) for local language understanding
- LM Studio for local model inference
- Native macOS APIs for application and window control

## Documentation

- [Product Requirements](docs/01_Flow_Unified_PRD.md)
- [Technical Specification](docs/02_Flow_Technical_Behavioral_Spec.md)
- [Implementation Plan](docs/03_Flow_Agent_Implementation_Plan.md)

## Development

Requirements: Xcode 27+/Swift 6.4, LM Studio local server on `http://localhost:1234/v1` with `ternary-bonsai-2-2b-mlx` loaded.

```
swift build                      # build all modules
swift test                       # unit tests (no server needed)
FLOW_LIVE_LLM=1 swift test       # plus live tests against LM Studio
scripts/build_app.sh --open      # build and launch build/Flow.app
```

`FLOW_LMSTUDIO_URL` and `FLOW_MODEL_ID` override the defaults; non-localhost URLs are refused.

Speech (Argmax Pro, SDK 3.1.8) comes from Argmax's authenticated Swift registry:

```
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token <SECRET_API_TOKEN>
cp .env.example .env             # then set ARGMAX_API_KEY (runtime key, ax_…); .env is git-ignored
scripts/flow_voice.sh --once     # mic → Argmax → Bonsai → mock consumer (executes nothing)
swift run flow-bench --runs 3 --out docs/evidence/T-002   # T-002 Bonsai benchmark
```

No registry access? `FLOW_DISABLE_ARGMAX=1 swift build` builds everything except the Argmax adapter.

Modules (SwiftPM):
- `FlowCore` — intents, typed action allowlist, risk tiers, errors, deterministic control router
- `FlowLLM` — LM Studio client, Bonsai prompt + JSON schema, strict validator, classifier
- `FlowAudio` — speech pipeline independent of any SDK: microphone consent, utterance endpointing (partial vs final), VAD, deterministic stop/cancel, routing to the classifier and an `IntentSink`
- `FlowArgmax` — Argmax Pro `LiveTranscriber` adapter implementing `SpeechTranscribing`
- `flow-voice` / `flow-bench` — Track B developer harnesses (voice → typed intent; Bonsai benchmark). Neither executes actions.
- `FlowApp` — SwiftUI shell: type a command, see the interpreted action (nothing is executed)

## Status

T-011 initial intent classifier (typed command → validated action preview). See [docs/evidence](docs/evidence).
