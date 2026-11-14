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

Modules (SwiftPM):
- `FlowCore` — intents, typed action allowlist, risk tiers, errors, deterministic control router
- `FlowLLM` — LM Studio client, Bonsai prompt + JSON schema, strict validator, classifier
- `FlowApp` — SwiftUI shell: type a command, see the interpreted action (nothing is executed)

## Status

T-011 initial intent classifier (typed command → validated action preview). See [docs/evidence](docs/evidence).
