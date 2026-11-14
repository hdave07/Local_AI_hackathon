# FLOW — AI Coding-Agent Implementation Plan
**Version:** 0.1 · **Date:** 2026-11-14 · **Goal:** Build an integrated, tested voice-first macOS prototype using Argmax, Bonsai 2 and LM Studio.

## 1. Instructions for every coding agent
Treat `01_Flow_Unified_PRD.md` as the product source of truth and `02_Flow_Technical_Behavioral_Spec.md` as the behavioral contract. Do not invent product features or silently downgrade requirements. If an external capability is unavailable, report a BLOCKER, provide reproduction steps and a recommended within-stack alternative; do not replace Argmax, Bonsai 2 or LM Studio without explicit team approval. Never log sensitive audio, mail bodies or credentials. No external send action without explicit user confirmation. No arbitrary LLM-produced shell or AppleScript code. Keep all changes small, tested, documented and reversible.

**Definition of done for each ticket:** (1) code compiles, (2) unit tests, (3) integration tests or honest simulator with mocks, (4) manual demo steps, (5) failure-path evidence, (6) contracts updated, (7) team-reproducible setup, (8) screenshots or short recorded proof when UI-dependent.

## 2. Recommended repository
```
Flow/
  README.md
  docs/                         # 01, 02, 03 and decision log
  FlowApp/                       # SwiftUI app + main HUD + wizard
  FlowCore/                      # contracts, states, actions, context
  FlowAudio/                     # Argmax transcription + TTS
  FlowLLM/                       # Bonsai runtime adapter, prompts, validation
  FlowAX/                        # AX inspector, resolver, overlays
  FlowWindow/                    # window geometry actions
  FlowMail/                      # hybrid Mail adapter
  FlowCalendar/                  # EventKit read adapter
  FlowText/                      # dictation, edit, rewrite previews
  FlowTests/                     # unit, integration, fixture tests
  fixtures/                      # safe synthetic mail/calendar data
  scripts/                       # dev preflight and benchmark harness
```
Separate package modules or folder targets are acceptable; module interfaces are mandatory. No direct imports between UI and individual app adapters except through FlowCore abstractions.

## 3. Shared type contracts to implement before parallel work
- `Utterance(id, stableText, language, timestamp, sessionID)`
- `AppWindowRef(appBundleID, pid, windowID, title, snapshotEpoch)`
- `AXTargetRef(appBundleID, windowID, elementPath, snapshotEpoch, role, title)`
- `TaskContext(activeWindow, selectedMessage, draftID, draftVersion, previousTarget, pendingQuestion)`
- `Intent(kind, target, args, confidenceSignal, risk)`
- `Plan(id, steps<=5, currentIndex, cancellationToken, userGoal)`
- `ActionResult(status, errorCode, evidence, retrySafe, undoToken)`
- `DraftSnapshot(subject, recipients, body, version, hash)`
- `ReviewAuthorization(draftHash, recipientHash, expiresAt, consumed)`

`confidenceSignal` is informational; not a substitute for deterministic target and safety checks. All adapters async, cancellable at safe checkpoints. Errors typed, never silent.

## 4. Dependency plan / gates
**Wave 0: environment and sponsor integration** (no other feature depends on unknown runtime assumptions after this gate).
- T-001 Mac environment inventory: exact macOS, chip, RAM, microphone, dev signing, Mail account, Calendar access. Deliver env matrix and test notes.
- T-002 LM Studio/Bonsai compatibility spike: install 2B/4B/9B supported formats; try structured output 30 prompts. Record load status, memory, latency, JSON conformance; DO NOT silently substitute another LLM. If unsupported, investigate PrismML server local option and sponsor-eligibility rules; issue decision gate.
- T-003 Argmax SDK spike: activate Pro license, stream stable/hypothesis transcription; VAD, model preload, optional runtime custom vocabulary with compatible backend; TTS. Record exact API/version, latency and compatibility.
- T-004 macOS automation spike: inspect AX trees and move windows, create/read visible Mail draft, use EventKit calendar data. Document denied permissions, versions, missing capabilities.
- T-005 skeleton SwiftUI app, capability readiness screen, dependency injection and mock adapters.

**Wave 1: shared core** (can parallelize only after type contracts).
- T-010 deterministic `FlowCore` state machine: transitions, interruptions, approval binding, session timeout.
- T-011 `ModelProvider` localhost HTTP client, schema validation, test prompts and mocked bad output.
- T-012 `AudioInput` Argmax adapter, wake detection, stable utterance pipeline, session commands, explicit dictation boundaries.
- T-013 `UIInspector` AX snapshot, tree inspection, element guards, `TargetResolver`, snapshot epoch invalidation.
- T-014 HUD and audio feedback: visual-first state, highlights, concise TTS, accessible recovery choices, no verbose default speech.
- T-015 `PermissionManager` guided first-launch wizard with capability probes, refusal/revocation paths.

**Wave 2: capability modules** (parallel after Wave 1 interfaces).
- T-020 `WindowExecutor`: activation/switch, frame snapshot, move, resize, tile, minimize, restore; deterministic undo.
- T-021 generic navigation: AX click, focus, scroll, labels/synonyms, numbered overlay scoped to snapshot; fallback stop.
- T-022 Mail adapter read/search: candidate search, stable identity, open visible message, disambiguation.
- T-023 Mail compose/reply/send: visible actual draft, recipient identity, review authorization, at-most-once send, status reconciliation.
- T-024 Calendar EventKit read: date/time zones, busy/tentative/unknown, insufficient authorization.
- T-025 `TextEditor`: literal dictation, exact edits, last-sentence/delete, snapshots, targeted undo, factual slot protection, semantic rewrite preview.
- T-026 context-aware planner: action allowlist, 5-step cap, safe clarifications, live state refresh before each action.

**Wave 3: integration and polish**.
- T-030 cross-module Mail+Calendar+windows integration test with live fixtures.
- T-031 fault injection: wrong recognition, duplicate target, stale overlay, Mail timeout, unavailable model, blocked permission.
- T-032 performance/quality benchmark 2B vs 4B vs 9B; freeze selected default and fallback tier, record measured values.
- T-033 offline test: disconnect Wi-Fi, perform window/nav/local drafting; separately test online Mail submission.
- T-034 optional Safari support: search, open result, read accessible content; clearly dependent on network and accessible page.
- T-035 demo assembly: integrated 90–150-second script and a deliberate recovery moment; 3 consecutive no-touch runs.

**Wave 4: optional only after acceptance**.
- T-040 optional gesture recognizer with interface `GestureIntent -> existing action`, off by default; not required to complete any task.
- T-041 experimental grid mouse or screenshot-based Bonsai 2 visual target resolver, guarded by user approval and benchmark accuracy; never run on stale coordinate claims.
- T-042 speaker verification research; no mandatory voice lock unless independently validated and recoverable.
- T-043 energy telemetry only if measurement methodology is defensible; otherwise label estimates.

## 5. Ticket templates / acceptance criteria
### T-002 — Bonsai + LM Studio spike
**Input:** three Bonsai 2 versions, compatible model packages, LM Studio current local build.
**Output:** adapter endpoint, runtime+model manifest, latency/validity CSV, recommendation.
**Acceptance:** at least one required Bonsai size loads; 30 JSON tasks give syntax-valid output and schema-validity rate recorded; deliberate bad candidate rejected by validator; network disabled test; record version-specific failures rather than fabricate compatibility. **Blocker:** cannot load required models under eligible runtime.

### T-003 — Argmax spike
**Input:** Pro key, model, microphone.
**Acceptance:** stable transcripts, hypothesis HUD, VAD segments, 20 phrases, no actions triggered by provisional hypothesis; document custom vocab behavior with selected ASR model; model available offline. **Blocker:** key/bundle IDs incompatible, selected speech model cannot deliver required features.

### T-010 — State machine
**Acceptance:** test legal and illegal transitions, cancel during plan, approval invalidation after draft mutation, dictation boundaries, session timeout. No LLM involved in stop/cancel semantics.

### T-020 — Windows
**Acceptance:** tile Mail/Calendar with observable bounds; move, resize, minimize, restore, switch and undo across 10 fixtures; handle two windows same app, unsupported size changes, unexpected full-screen. Every success confirmed by post-action measurement.

### T-021 — AX generic navigation
**Acceptance:** show numbered overlay in at least two accessible native apps; choose correct live control; stale number rejected after layout update; scroll and focus verified; no arbitrary coordinate click from model.

### T-022 / T-023 — Mail
**Acceptance:** seeded message retrieved by sender+subject; ambiguous Sarah contacts require clarification; reply preserves correct recipient; actual Mail compose UI shows exact contents; rewritten draft previewed; send without review does not immediately send; fresh approval bound to exact version; send timeout does not duplicate.

### T-024 — Calendar
**Acceptance:** event in calendar detected correctly; tentative vs busy differentiated; all-day and timezone handled; missing permission -> unknown with useful setup direction; no false free claim.

### T-025 — Dictation/edit
**Acceptance:** standalone exit phrase works; ordinary sentence beginning 'delete' inserted literally; change 3 -> 3:30 affects correct span only; repeated phrase asks for disambiguation; substantial rewrite requires preview; undo restores verified snapshot.

### T-026 — Planner/executor
**Acceptance:** finite action allowlist; <=5 steps per plan; validation rejects unknown tool/target; current UI reinspection per step; no send without approval; stop at safe checkpoint; bounded retries and helpful 2-alternative prompt.

### T-035 — Demo
**Acceptance:** 3/3 consecutive live runs after permissions; no keyboard or mouse touched; actual app windows and draft visibly update; explicit error-recovery moment; measured runtimes; Wi-Fi-off model behavior demonstrated separately from external send.

## 6. Agent task prompt — reusable
```text
You are implementing ticket [ID] in the Flow repository.
Read docs/01_Flow_Unified_PRD.md and docs/02_Flow_Technical_Behavioral_Spec.md.
Implement only [ticket] and its declared interfaces. Do not broaden scope.
Required stack: Argmax Pro for speech, Bonsai 2 2B/4B/9B for language
understanding, LM Studio target local runtime. No cloud replacement.
Keep safety invariants: no unapproved consequential actions; never act on
stale UI targets; verified outcomes; cancellation at safe checkpoints.
Before coding: summarize assumptions, dependencies, and potential blockers.
After coding: report modified files, compilation/test commands and results,
manual steps, known failures, and next integration action. If blocked,
return BLOCKER with diagnostics; do not invent platform APIs.
```

## 7. Shared multi-agent working rules
- Agent A owns core models/state/contracts; agents B/C/D depend on its merged interface tags.
- Agents work in separate branches/worktrees. One integrator reviews API changes and conflicts.
- Freeze protocol/interface changes via an architecture decision record (ADR); no parallel redefinitions of message/draft IDs.
- Mocks may support tests, but video demos must distinguish mocks from live Mail/Calendar interactions.
- Keep scripts safe: never auto-send real emails as part of unit tests; use dedicated test accounts and recipient whitelist.
- Each integration gate produces a 5-minute manual reproduction path and evidence stored under `docs/evidence` (without sensitive data).

## 8. Test matrix and demo-day checklist
**Environment:** frozen macOS build, Apple Silicon, known installed Mail+Calendar versions, bundled/downloaded model assets, microphone, test Mail account, local seeded events, all relevant permissions.
**Happy paths:** open/arrange apps; locate message; query availability; draft/revise; optional readback; confirm send; undo window move.
**Adversarial paths:** two Sarahs, duplicate Reply buttons, ambiguous 'that', dictation containing command verbs, offline Mail, stale overlay, user interruption, AX denial, microphone lost, malformed Bonsai JSON, timeout during send.
**Accessibility:** entire guaranteed flow voice-only after setup, no tiny text-only safety warning, concise audio prompt for important approvals, all recovery choices speakable.
**Privacy:** no saved secret logs, no external inference, localhost service bound appropriately.
**Demo:** never claim Mail delivery purely from click; preflight model load; check Wi-Fi-independent tasks; have Notes-based alternative only if framed as a documented backup capability.

## 9. Stop / go criteria
**GO for feature implementation** only after T-002/T-003/T-004 verify a workable path for required sponsors and system automation. **GO for demo rehearsal** only after at least one end-to-end mail draft, one calendar query, and window tiling work live. **NO-GO for sending** if exact-recipient, content-hash confirmation or send reconciliation fails. **NO-GO for claiming universal accessibility** without independent disabled-user testing.

## 10. Known blocker register to review with team
| ID | Severity | Decision required |
|---|---|---|
| B-01 | Critical | Exact Bonsai checkpoint and LM Studio engine compatibility |
| B-02 | Critical | Argmax Pro license/model versions and supported speech model for custom vocabulary |
| B-03 | High | Mail automation API support + UI verification on installed OS |
| B-04 | High | Permissions, signing and first-launch assistance route |
| B-05 | High | Machine RAM/chip, model latency and TTS-microphone interference |
| B-06 | Medium | Calendar availability interpretation across accessible calendars |
| B-07 | Medium | Whether optional visual/grid targeting ships without threatening core reliability |
| B-08 | Medium | Hackathon rules governing alternate local PrismML server if LM Studio loader fails |

## 11. Reference links
https://github.com/PrismML-Eng/Bonsai-demo
https://app.argmaxinc.com/docs
https://app.argmaxinc.com/docs/examples/custom-vocabulary
https://lmstudio.ai/docs/developer/openai-compat/structured-output
