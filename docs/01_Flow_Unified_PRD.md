# FLOW — Unified Product Requirements Document
**Version:** 0.1 · **Status:** Implementation-ready draft with documented gates · **Date:** 2026-11-14

## 1. Executive definition
Flow is a voice-first macOS assistant designed primarily for people with limited upper-limb mobility who retain sufficiently reliable speech for computer interaction. It helps users complete everyday tasks with less physical, verbal and cognitive effort, while keeping them informed and in control. Natural-language instructions cover application navigation, window management, reading calendar information, finding mail, drafting and correcting text, and approved sending. Core inference runs locally. Optional gestures are supplementary and never required.

**One-liner:** An offline-capable, voice-first Mac assistant that turns natural instructions into verified computer actions and lets people with limited hand mobility complete and correct tasks without using a keyboard or mouse once configured.

**Central outcome:** A user can organize windows, navigate Mail and Calendar, prepare and revise a message, review and send it, recover from common errors, and complete the entire supported flow by voice.

## 2. Source reconciliation and decisions
Source A: *Hands-Free Mac — Product Definition* (12 pages, November 14, 2026) contributed Argmax/Bonsai/LM Studio, deterministic command paths, navigation overlays, editing, local processing, confirmations, and recovery. Source B: *PRD: Hands-Free Computer Control* (5 pages) contributed Flow naming, optional gestures, visual window-management demonstration and app switching. Conversation decisions override incompatible proposals from either source.

**Settled decisions (D-001 to D-018):**
- D-001 Primary users have limited hand or upper-limb mobility and reliable speech; do not claim universal ALS suitability.
- D-002 Voice is the complete primary interface after setup; gestures are optional stretch functionality.
- D-003 Integrated demonstration: arrange windows, navigate messages and scheduling, compose, correct, review and send.
- D-004 Native macOS apps first; Mail and Calendar anchor the experience, Finder/Notes/Safari have limited generic coverage.
- D-005 Bounded multi-step plans, not unrestricted autonomous execution.
- D-006 All core speech, inference and action decisions processed locally; online services can still require internet.
- D-007 Balance reliable accessibility with a visually legible demonstration.
- D-008 Support wake-word and continuous sessions, switchable by voice, with configurable inactivity timeout.
- D-009 Visual status by default; audio on request, for necessary clarification and consequential safety prompts.
- D-010 Ordinary commands, editing and multi-step tasks are automatically routed; protected literal dictation uses a reserved exit phrase.
- D-011 Safe actions automatic; targeted edits applied with undo; substantial rewrites previewed; sending/deletion requires explicit confirmation.
- D-012 Recent task context plus verified live UI; clarify when they conflict or multiple consequential targets exist.
- D-013 Ambiguous low-risk geometry may use predictable defaults; consequential target ambiguity is never silently resolved.
- D-014 Recover with bounded predefined strategies, then stop and offer concise voice-operable alternatives.
- D-015 Calendar uses local EventKit read integration where permitted, and native UI for visible interactions; busy/tentative/unknown are distinguished.
- D-016 Mail supports find/read, reply, compose, edit, review and send using a hybrid native/UI strategy with actual visible results.
- D-017 Window control includes move/resize/tile/switch/minimize/restore/multi-window on one display first.
- D-018 One-time guided permission onboarding, with explicit authorization and assistance where macOS requires it.

## 3. User/problem boundaries
**Primary persona:** can speak usable commands, cannot comfortably or reliably use keyboard or pointer; may need to operate independently after assisted initial setup. **Secondary:** person with temporary injury or RSI who benefits from less repeated input. **Excluded guarantee:** people who cannot reliably speak, users requiring a full screen reader or AAC, or people who cannot complete initial OS authorizations without external assistance.

Problem is not the total absence of voice controls on Mac: Apple Voice Control and Talon already offer extensive navigation and editing. Flow's hypothesis is that task-level natural language and targeted, reversible corrections reduce effort while preserving predictable execution. Claims of improvement require baseline measurements, not merely a polished demo.

## 4. Design principles (in priority order)
1. **No silent consequential errors:** identify targets, verify state, require approval before sending/deleting.
2. **Do not strand the user within guaranteed workflows:** voice-operated commands, clarification, numbered selections, undo/recovery if speech remains functioning.
3. **Minimize effort:** fewest reasonable spoken words, interactions, manual steps and confirmations—not merely minimum model calls.
4. **Transparent state:** user can see listening/planning/acting/reviewing/blocked status; optional concise speech.
5. **Deterministic when possible:** direct commands and geometric operations use ordinary code; Bonsai interprets intentions and limited plans.
6. **Local-first privacy:** core inference and audio stay local; no cloud-model fallback.
7. **Honest capability boundaries:** general support where AX exposes controls, guarantee only explicitly tested flows.

## 5. Feature scope / release tiers
| Feature | MVP P0 | P1 | Stretch/P2 |
|---|---|---|---|
| Wake word + continuous sessions + VAD | Yes | Advanced voice calibration | Speaker identification |
| Argmax live transcription | Yes | Contextual keyword adaptation if compatible | Multi-speaker enhancements |
| Bonsai natural-language router | Yes | Dynamic escalation 2B/4B/9B | More generalized agent tasks |
| Local LM Studio integration | Required target, gated by compatibility | Alternate local Bonsai runtime contingency | — |
| HUD, progress, cancellation | Yes | Expanded preferences | Energy measurements |
| Window move/resize/tile/switch/minimize/restore | Yes on primary display | Multi-display | Advanced layouts |
| Generic app launch, AX click, scroll, navigation | Yes | Safari search and reading | Local screenshot/grid targeting |
| Numbered AX overlay | Yes | Hierarchical group navigation | Coordinate grid |
| Mail find/read/compose/reply/edit/review/send | Yes | Forward/archive/search refinements | Other mail clients |
| Calendar read availability | Yes | More calendar sources/view navigation | Create/reschedule events |
| Literal dictation/targeted edits | Yes | Rich formatting controls | Code dictation |
| Semantic rewrite preview, restore | Yes | Improved comparison and explanations | — |
| Gesture controls | No | Interface contract only | Optional implemented gestures |

**Non-goals:** arbitrary long-running autonomy; full OS accessibility across inaccessible canvases; universal speech impairment support; automatic security permission bypass; guaranteeing message delivery; automatically granting required macOS permissions.

## 6. Flagship end-to-end user journey
**Demo data** should be seeded, non-sensitive and deterministic. Example: an email from Sarah about meeting, and Calendar containing an event or tentative conflict.

1. User starts session by voice; HUD shows 'Listening'.
2. 'Open Mail and Calendar and put them side by side.' Flow launches/activates, tiles and verifies both windows; minimal visual feedback.
3. 'Find Sarah's email about tomorrow.' Flow searches/open correct message; if similar matches exist, it offers brief disambiguation.
4. 'Check whether I have anything at four tomorrow.' EventKit retrieves authorized events; availability shown as busy, tentative, free-in-accessible-calendars or uncertain. Time zone appears if ambiguous.
5. 'Reply that I can meet, but ask if we can move it to four.' Flow drafts in actual Mail UI, unsent. Named recipient and draft displayed.
6. 'Actually make that four thirty and sound more formal.' Targeted time change applies immediately; substantial tone rewrite is previewed before commitment.
7. 'Read my draft' (optional). Local TTS reads content without excessive narration.
8. 'Send it.' Flow moves to review-ready/confirmation flow, shows the exact recipient and current message version and asks for explicit spoken approval; sending disabled if target or draft changed.
9. Flow submits through Mail and verifies a meaningful send status; cannot promise delivery.
10. Include one deliberate ambiguity/error branch (two Sarahs, missing button, or invalid plan) in demonstration; recover by voice.

## 7. Key experience contracts
### 7.1 Activation
Wake-word-per-request mode is default; 'start a session' enables follow-up commands until voice 'end session' or configurable inactivity timeout. During paused listening the application retains only minimal activation detection; standalone 'Flow, resume listening' reactivates. Emergency stop/cancel operate whenever microphone access permits. False activation test required.

### 7.2 Language and dictation
Default commands include direct actions, semantic edits and short bounded tasks without explicit mode changes. 'Start dictation' enters literal dictation; protected standalone 'Flow, stop dictation' exits; standalone 'Flow, stop' interrupts. Command phrases embedded in larger dictated sentences remain text. No mandatory support for inserting reserved phrase literally in MVP.

### 7.3 Clarification
If one live target uniquely fits, execute allowed low-risk steps. If same app multiple windows but focus/context disambiguates, use that evidence. For distinct matching recipients, messages or consequential targets, ask which (voice answer by descriptive name or number). Avoid confident guesses based solely on LLM score.

### 7.4 Feedback
Routine action: HUD only. Long task: HUD progress with target highlight. Clarification: short prompt spoken if needed. Sending/deleting: concise spoken confirmation of target; full readback available on request. On failure: after automatic bounded attempts, one-line reason and maximum two alternatives plus cancel. Low vision is not a guaranteed primary persona; user can enable spoken status preference later.

### 7.5 Review and authorization
Targeted edits applied directly with undo history and visible diff/highlight. AI semantic rewrites previewed against saved previous draft; accept or discard. A draft may not transition from newly generated to externally sent without a dedicated review-ready presentation and explicit separate send approval; review can be visual, with spoken readback on request. Approval tied to exact message body, recipients and version, invalidated by edits.

### 7.6 Undo
Flow-managed snapshots for window geometry and authored draft changes. Application Undo only where state and focus safely verified. Send/delivery cannot be guaranteed reversible. Repeat undo walks only known reversible changes, stopping where state no longer matches expectations.

## 8. Navigation coverage policy
**Tier A: Proven workflows**: required Mail, Calendar, windows and Notes fallback, tested across a frozen OS/app configuration.
**Tier B: Generic AX support**: app activation, scroll, click, focus, recognized text entry and numbered overlay across accessible native apps, without app-specific guarantee.
**Tier C: Experimental extension**: screenshot interpretation using the required Bonsai family if runtime supports vision, coordinate grid, or other fallback. Such features are not prerequisites for the core demo and must not execute on uncertain targets without confirmation.
**Tier D: Unsupported**: honest explanation and voice-safe exit; no fabricated success.

## 9. Permissions and privacy
A unified onboarding wizard checks microphone, Accessibility control, Automation/Apple Events as needed, Calendar access, and local runtime readiness. macOS consent cannot be self-granted. Explain steps and offer existing macOS Voice Control or helper assistance for first authorization. Do not promise independent first-run enrollment under all configurations. Do not persist microphone audio or message bodies by default. Prevent sensitive/secure fields from becoming model context. Model server binds localhost only by default; document logs and purge option.

## 10. Product success metrics
- 100% of chosen flagship tasks complete without touching keyboard/mouse after pre-authorization across three consecutive recorded runs.
- 0 unapproved sends/deletions in adversarial test suite.
- 100% of consequential target ambiguity cases ask/stop rather than guess.
- >=95% success on the frozen scripted low-risk command suite (target for demo; measured).
- No unhandled dead ends in tested guaranteed workflows; microphone/OS failures explicitly exempt and reported.
- Median fast-path latency <1.5 s and planned-command initial feedback <3 s (targets pending benchmark, not guarantees).
- Measure speech words, command count, task time, repetitions and error recovery compared with Apple Voice Control.
- Demonstrate offline command and draft operations with Wi-Fi disabled; Mail network sending is explicitly separate.

## 11. Demo, judging and honesty
The 90–150-second demo should lead with visual window tiling, move to contextual Mail/Calendar reasoning, show draft correction and control, then trigger a safe, explicit send confirmation. Display Argmax transcription, Bonsai model tier and local LM Studio runtime status unobtrusively. Demonstrate one real recovery. If connectivity is off, show draft/send approval but do not claim external mail delivery. Have prerecorded local test fixtures and a live fallback path; never represent a scripted mock as live behavior.

## 12. Open gates — do not silently invent answers
G-01 Verify Bonsai 2 2B/4B/9B model format actually loads in available LM Studio engine; if not, confirm eligibility of PrismML local runtime as contingency while retaining LM Studio in project/demo toolchain.
G-02 Benchmark Bonsai structured output conformance and speed on actual hackathon Mac; 2B vs 4B vs 9B chosen empirically.
G-03 Argmax Pro license, bundle ID, OS and model compatibility; confirm realtime STT + custom vocab for selected ASR backend.
G-04 Determine Mail native automation capabilities and observed UI sync, search, draft and send verification on installed macOS/Mail.
G-05 Verify EventKit calendar access scope, permissions and event availability semantics in chosen OS.
G-06 Confirm wake word and interruption behavior under TTS and ambient conversation.
G-07 Confirm exact demonstration machine model, macOS release, RAM and app accounts before locking acceptance environment.
G-08 Test numbered overlay coverage and decide if an optional P1 grid/vision fallback is worth shipping.
G-09 Decide which demo operations need real network connectivity and establish mock-fixture fallback explicitly.
G-10 Confirm that first-run macOS system permissions can be completed through built-in macOS accessibility features or with helper assistance.

## 13. Reference URLs
- PrismML Bonsai 2 release: https://prismml.com/news/bonsai-2-family
- PrismML example runtime: https://github.com/PrismML-Eng/Bonsai-demo
- Argmax docs: https://app.argmaxinc.com/docs
- Argmax custom vocabulary: https://app.argmaxinc.com/docs/examples/custom-vocabulary
- LM Studio structured output: https://lmstudio.ai/docs/developer/openai-compat/structured-output
- Baseline: Apple macOS Voice Control documentation, Apple accessibility and EventKit developer documentation.
