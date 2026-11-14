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
FLOW_LIVE_AX=1 swift test        # plus live window tests (moves your real Notes window, then restores it)
scripts/build_app.sh --open      # build and launch build/Flow.app
.build/debug/flowctl "activate notes" "move notes left_half" "undo"   # typed window commands
```

Window control needs Accessibility permission for whichever app runs it (Flow.app, or the terminal/IDE running `swift test` / `flowctl`).

**Signing:** `scripts/build_app.sh` signs Flow.app with a stable identity (`$FLOW_SIGN_IDENTITY`, else an "Apple Development" certificate, else the local identity from `scripts/create_local_signing_identity.sh`) so macOS keeps Flow's Accessibility grant across rebuilds. It refuses to sign ad hoc unless `--allow-adhoc` is passed, because ad-hoc grants are tied to one binary hash. If signing fails with `errSecInternalComponent`, make sure Apple's WWDR G3 intermediate certificate is installed, and allow `codesign` when Keychain asks for key access.

`FLOW_LMSTUDIO_URL` and `FLOW_MODEL_ID` override the defaults; non-localhost URLs are refused.

Modules (SwiftPM):
- `FlowCore` — intents, typed action allowlist, risk tiers, errors, deterministic control router
- `FlowLLM` — LM Studio client, Bonsai prompt + JSON schema, strict validator, classifier
- `FlowWindow` — app launch/switch and window move/resize/tile/minimize/restore via Accessibility, verified re-reads, undo
- `FlowApp` — SwiftUI shell: "Interpret" tab (classifier preview, nothing executed) and "Window Control" tab (typed window commands)
- `flowctl` — command-line typed interface to FlowWindow

## Status

- T-011 initial intent classifier (typed command → validated action preview)
- T-020 window control foundation (typed commands on real windows, verified, undoable)

See [docs/evidence](docs/evidence) and [docs/adr](docs/adr).
