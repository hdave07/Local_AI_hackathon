# T-031 evidence — voice → plan → real executor (Flow.app)

**Date:** 2026-11-14 · **Branch:** `feature/voice-executor-integration` (from main 57717c0) · **Machine:** macOS 26.6.2, Stage Manager on, LM Studio + `ternary-bonsai-2-2b-mlx`, Argmax Pro (key in the user's login Keychain).

## What was built
- **`FlowExecutor.MacPlanExecutor: PlanExecuting`:** the real executor (ADR 0005 table), backed by FlowWindow, FlowAX and FlowMail.
  - Mail is in **test-mode scope**: FlowTest mailbox only.
  - **Drafting, editing, review, send and calendar are disabled** (`unsupported`, nothing changed).
  - FlowAX refuses Send/Delete/Discard/Trash/Erase controls.
- **`FlowSession.VoiceSessionCoordinator`:** `VoicePipeline` → `TaskSession`, with routing done once and no second task store. Stop/cancel take priority; HUD status; typed input on the same path.
- **Flow.app "Voice" tab:**
  - Start/Stop listening, live status, last heard, Flow's replies, numbered choices, typed input, turn and executor logs.
  - Argmax key saved to the Keychain; `NSMicrophoneUsageDescription` added.
  - `build_app.sh` now bundles `libArgmaxOSSDynamic.dylib` and `ArgmaxSDK.framework`; the framework keeps Argmax's signature.
- **ADR 0007** documents the interfaces.

## Live results: spoken, in Flow.app
| Spoken (Argmax finalized) | Flow | Executor | Handling time |
|---|---|---|---|
| "Just the same thing." (not meant for Flow) | "I didn't catch what to do…" | nothing executed | 22.4 s (Bonsai cold start) |
| "Um, open notes" (before fix) | "Say or type a command." | nothing | 13 ms |
| **"Open notes"** | plan "Open Notes" → completed | `activate_app → completed · Notes is in front` | **0.65 s** |
| "Can you open mail?" | plan "Open Mail" → completed | `activate_app → completed · Mail is in front` | 0.91 s |
| **"Um, open notes"** (after fix) | completed | Notes in front | 0.63 s |
| **"Can you find Sarah's email?"** | "I found 3 messages: 1. Sarah Chen …; 2. Sarah Okafor …; 3. Sarah Chen …. Which one?" | Mail activated; `read_message → needs_clarification · 3 candidate messages` (FlowTest only) | 1.6 s |
| "I meant Sarah Chen." (before narrowing fix) | repeated the full list | nothing | 15.4 s (fell through to Bonsai) |
| **"Yeah, the first one"** | completed | `read_message → completed · opened: Sarah Chen — “[FlowTest] Meeting tomorrow”` | 5.6 s |
| "And can you reply to it?" / "I want to reply to this email." / "…meet instead at 4:30?" / "Mail" | unrelated questions, then opened Mail | only `activate_app Mail` | 2–6.7 s each |

**Milestone 1 (spoken "Open Notes" → Notes verified frontmost) passed. Milestone 2 (spoken search → clarification → spoken choice → synthetic message opened and verified) passed.** No real inbox message was searched or opened: the executor forces FlowTest scope.

## Live results: typed path in Flow.app (same coordinator and executor)
- "Open Notes": plan Open Notes; `activate_app → completed`; Notes frontmost (~7 s round trip in the drive script, including UI waits).
- "Find Sarah's email" → 3 FlowTest candidates; "the second one" → "[FlowTest] Lunch on Friday?" from Sarah Okafor opened and verified.

## Automated results
`FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 swift test`: **all passed** (405 before the probe cleanup).

| Suite | Result |
|---|---|
| FlowExecutorTests: simulated macOS (21) + **live real executor (3)** | 24 passed |
| FlowSessionTests: coordinator with MockExecutor (17) + phrase plans (2 parameterized) | 19 passed |
| FlowPlannerTests (incl. new filler and narrowing regressions) | 42 passed |
| FlowAX 61, FlowMail 44, FlowWindow 48, FlowRouting 62, others | passed |

Live executor tests (real router + planner, model disabled, real Notes / FlowTest):
1. "Open Notes": completed, `NSWorkspace.frontmostApplication` = Notes, context `activeApp = .notes`.
2. "Find Sarah's email": paused with 3 candidates, all `[FlowTest]` / `@example.invalid`, two distinct Sarahs. "Sarah Okafor": opened "[FlowTest] Lunch on Friday?", completed only with title and body on screen.
3. "reply to it saying test only" / "send it": no `create_draft` or `request_send` completed.

## Bugs found live and fixed
1. **Packaging:** Flow.app crashed at launch (missing `libArgmaxOSSDynamic.dylib`). `build_app.sh` now bundles `@rpath` dependencies.
2. **Unstable message ids:** `JSONEncoder` key order made the same message encode differently, and the runner rejected verified opens. Now encoded with sorted keys.
3. **Filler clauses (FlowPlanner):** "Um, open notes" split into "Um" + "open notes", and "Um" failed the whole utterance. Filler-only clauses are now dropped.
4. **Partial answers (FlowPlanner):** "I meant Sarah Chen" when 2 of 3 candidates are hers now narrows the question to those 2, instead of repeating all 3 (and no longer falls through to Bonsai).
5. **HUD:** router questions ("Which app?") now show as `awaitingAnswer`.

## Not done / limitations
- **Reply (and any drafting) is not implemented.** The executor returns `unsupported` for `create_draft`. Fully specified "reply to it saying …" plans correctly. Underspecified "reply to it" / "I want to reply to this email" isn't understood deterministically; Bonsai then asks unrelated questions, and "Mail" was taken as an answer and opened Mail.
- **Bonsai latency:** 15–22 s when cold. Utterances outside the deterministic paths are slow, and ambient speech gets classified (it was declined safely in this run).
- **No spoken output (TTS):** replies appear in the HUD only.
- **FlowAX numbered choices** can't resume a plan (ADR 0005 §4).
- **Mail scope:** the FlowTest-only scope is fixed in Flow.app for this milestone.
- **Stage Manager:** activating Mail sometimes reports "no open window", while frontmost is still verified.
