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
.build/debug/flowctl "click seven in Calculator" "show numbers in Calculator" "choose 25"   # typed UI navigation
swift build --product flow-nav-fixture && FLOW_LIVE_AX=1 swift test --filter FlowAXTests   # live navigation tests
.build/debug/flowctl "mail find mail from sarah in mailbox FlowTest" "mail choose 2" "mail read it"   # typed Mail commands
FLOW_LIVE_MAIL=1 swift test --filter FlowMailTests   # live Mail tests (import fixtures/mail/FlowTest.mbox into Mail first)
```

Window control needs Accessibility permission for whichever app runs it (Flow.app, or the terminal/IDE running `swift test` / `flowctl`).

**Signing:** `scripts/build_app.sh` signs Flow.app with a stable identity (`$FLOW_SIGN_IDENTITY`, else an "Apple Development" certificate, else the local identity from `scripts/create_local_signing_identity.sh`) so macOS keeps Flow's Accessibility grant across rebuilds. It refuses to sign ad hoc unless `--allow-adhoc` is passed, because ad-hoc grants are tied to one binary hash. If signing fails with `errSecInternalComponent`, make sure Apple's WWDR G3 intermediate certificate is installed, and allow `codesign` when Keychain asks for key access.

`FLOW_LMSTUDIO_URL` and `FLOW_MODEL_ID` override the defaults; non-localhost URLs are refused.

Speech (Argmax Pro, SDK 3.1.8) comes from Argmax's authenticated Swift registry:

```
swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token <SECRET_API_TOKEN>
cp .env.example .env             # then set ARGMAX_API_KEY (runtime key, ax_…); .env is git-ignored
scripts/flow_voice.sh --once     # mic → Argmax → Bonsai → mock consumer (executes nothing)
swift run flow-bench --runs 3 --out docs/evidence/T-002   # T-002 Bonsai benchmark
```

No registry access? `FLOW_DISABLE_ARGMAX=1 swift build` builds everything except the Argmax adapter. Note: that mode removes `Package.resolved` locally (no dependencies to pin). Do not commit the deletion; restore it with `git checkout -- Package.resolved`.

Modules (SwiftPM):
- `FlowCore` — intents, typed action allowlist, risk tiers, errors, deterministic control router
- `FlowLLM` — LM Studio client, Bonsai prompt + JSON schema, strict validator, classifier
- `FlowWindow` — app launch/switch and window move/resize/tile/minimize/restore via Accessibility, verified re-reads, undo
- `FlowAudio` — speech pipeline independent of any SDK: microphone consent, utterance endpointing (partial vs final), VAD, deterministic stop/cancel, routing to the classifier and an `IntentSink`
- `FlowArgmax` — Argmax Pro `LiveTranscriber` adapter implementing `SpeechTranscribing`
- `FlowRouting` — intent router: stop/cancel, deterministic fast path, task context and references, clarification with follow-up answers, Bonsai fallback with slot grounding (proposes intents; executes nothing)
- `FlowPlanner` — bounded multi-step planner (≤5 allowlisted steps), plan runner with pause/resume, bound single-use send approvals, at-most-once send ledger; channel-agnostic (Mail, Messages, WhatsApp, …); talks to macOS only through `PlanExecuting` (Track A)
- `FlowApp` — SwiftUI shell with typed-command tabs: "Interpret" (classifier preview, nothing executed), "Window Control", "UI Navigation", "Mail" (read-only) and "Voice" (spoken or typed commands → plan → real executor)
- `FlowAX` — generic UI navigation: AX inspection, deterministic target resolution, revalidated click/focus/select/scroll with verification, numbered overlay
- `FlowMail` — read-only Apple Mail search/open/read: Mail scripting (JSON over osascript), stable message refs with revalidation, on-screen verification via FlowAX
- `FlowExecutor` — real `PlanExecuting` adapter (FlowWindow, FlowAX, FlowMail); Mail limited to the FlowTest test mailbox; drafting/sending disabled
- `FlowSession` — `VoiceSessionCoordinator`: Argmax utterances → TaskSession (router + planner) → executor, with stop/cancel priority and HUD status
- `flowctl` — command-line typed interface to FlowWindow, FlowAX and FlowMail
- `flow-nav-fixture` — small AppKit app used by FlowAX live tests
- `flow-voice` / `flow-bench` / `flow-speech-eval` / `flow-plan-demo` — Track B developer harnesses (voice → typed intent; intent benchmark; synthesized-speech ASR and segmentation evaluation; planner walkthrough against a mock executor). None executes actions.

## Status

- T-011 initial intent classifier (typed command → validated action preview)
- T-020 window control foundation (typed commands on real windows, verified, undoable)
- T-021 generic UI navigation (typed commands on real apps, clarification, numbered overlay, stale-target refusal)
- T-022 Apple Mail read and search (read-only; synthetic FlowTest mailbox for live tests)
- T-031 voice → plan → real executor in Flow.app (spoken "Open Notes" and Mail search/choose verified live; see docs/evidence/T-031-voice-executor-integration.md, ADR 0007)
- T-003/T-012 Argmax voice pipeline: spoken command → confirmed utterance → validated intent → mock consumer (nothing executed)
- T-002 Bonsai benchmark harness and results
- T-026 bounded task planner, execution safety and task state against a mock executor (see docs/evidence/T-026-task-planner.md, ADR 0005)
- T-030 voice-to-intent reliability: router, task context, clarification, ASR robustness, segmentation (see docs/evidence/T-030-voice-improvements.md)

See [docs/evidence](docs/evidence) and [docs/adr](docs/adr).
