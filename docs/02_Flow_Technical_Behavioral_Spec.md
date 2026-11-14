# FLOW — Technical and Behavioral Specification
**Version:** 0.1 · **Date:** 2026-11-14 · **Status:** Proposed contracts; gated integrations identified

## 1. Architectural boundaries
Local native Swift/SwiftUI macOS shell with status HUD and permission wizard. Argmax Pro streaming ASR supplies finalized text; optional interim hypotheses display only, never directly trigger consequential actions. A deterministic control router handles reserved phrases, session state and established commands. Bonsai 2 (2B/4B/9B) interprets ambiguous natural-language intents using the selected local LM Studio server, subject to compatibility validation. Planner produces schema-validated steps from a finite allowlist. Executor maps steps to native app automation, macOS AXUIElement operations, and local EventKit calendar queries; verifies outcomes against live UI/data. Local TTS offers requested readback and safety prompts.

**Trust boundary:** The LLM proposes intent and allowed actions; it cannot directly call arbitrary shell commands, AppleScript, network endpoints, file paths or raw coordinates. All tool arguments validated against fresh identifiers and allowlisted capabilities.

## 2. Module map (interfaces)
- `AudioInput`: select microphone, permissions, VAD, stable transcript segments, errors.
- `WakeSession`: wake detection, active sessions, pause/resume, inactivity timeout, interruption priority.
- `RecognitionContext`: dynamic names/labels for Argmax custom vocabulary only if proven compatible.
- `IntentRouter`: classify DIRECT, EDIT, DICTATE, TASK, CLARIFY, CONFIRM, CONTROL, UNSUPPORTED.
- `TaskContext`: active application, window, message ID, draft version, selected recipient, last editable reference; invalidate on UI changes.
- `UIInspector`: capture AX element tree with roles, title, enabled state, app/window stable ID, geometry, snapshot epoch.
- `TargetResolver`: match intent to current elements, detect ties, return unique / clarify / unavailable.
- `WindowExecutor`: launch/switch/move/resize/tile/minimize/restore and snapshots for undo.
- `MailAdapter`: find/read/compose/reply/edit/review/send; hybrid native application automation + visible AX.
- `CalendarAdapter`: read authorized local EventKit data; time-zone conversion and availability classification.
- `TextEditor`: protected dictation buffer; exact replacements, semantic rewrite preview, versioned undo.
- `PlanExecutor`: finite step execution, interrupt points, retry policy, verification, rollback policies.
- `HUDAndSpeech`: status, highlights, evidence, concise prompts, TTS ducking and playback interruption.
- `PermissionManager`: first-run wizard, capability probes, reconnect diagnostics.
- `Metrics`: latency/errors/attempt counts, optionally user-approved privacy-safe traces; exclude message bodies and audio by default.

## 3. Finite states and transitions
`DISABLED` -> onboarding/permissions -> `WAKE_IDLE` -> wake -> `LISTENING` -> finalized utterance -> `ROUTING`.
`ROUTING` -> `DICTATING`, `PLANNING`, `CLARIFYING`, `REVIEWING`, `CONFIRMING`, `EXECUTING`, `UNSUPPORTED` or `WAKE_IDLE`.
`PLANNING` -> validated actions -> `EXECUTING`, ambiguity -> `CLARIFYING`, schema error -> `RECOVERING`.
`EXECUTING` -> step verified -> next step; completed -> `SESSION_IDLE` or `WAKE_IDLE`; failed -> `RECOVERING`; stop -> `INTERRUPTED`.
`RECOVERING` -> bounded retry -> `EXECUTING`; exhaustion -> `CLARIFYING` or `BLOCKED`.
`DICTATING` -> standalone 'Flow, stop dictation' -> active-session normal command state; stop -> `INTERRUPTED`.
`REVIEWING` -> accept edit -> draft version update; discard -> previous state; send request -> `CONFIRMING` only after current version presented.
`CONFIRMING` -> exact spoken yes + current version and target match -> sensitive operation; no/cancel/timeout -> no action.
`SESSION_IDLE` -> next command; inactivity expiry -> `WAKE_IDLE`.

### Global invariants
- STOP/CANCEL has priority over LLM calls and at safe executor checkpoints; cannot reverse already committed side effects.
- No action on partial ASR hypotheses; exception: early interrupt detection may use specialized validation and must be tested for false positives.
- No stale AX identifiers: each action revalidates window and snapshot epoch.
- Every external send is at-most-once from Flow until outcome reconciled; no unverified retry.
- Content review/approval binds SHA-256 of normalized body, recipient list, subject, draft version; any change invalidates approval.
- Model outputs are untrusted and never execute directly.

## 4. Schemas (illustrative JSON contract)
```json
{
  "intent_id":"uuid",
  "kind":"direct|edit|task|dictation|clarification|confirmation|control|unsupported",
  "summary":"short user-visible summary",
  "target":{"type":"window|ax_element|message|draft|calendar|none","id":"live-id-or-null","snapshot_epoch":12},
  "actions":[{"type":"activate_app|move_window|resize_window|tile_windows|click_element|scroll|focus|insert_text|replace_text|create_draft|read_message|query_calendar|request_review|request_send","args":{},"risk":"low|content|external"}],
  "requires_clarification":false,
  "alternatives":[]
}
```
Validate allowed action type, argument types/ranges, max five steps per plan (config constant), live target identity, no extraneous keys for irreversible calls, and no nested arbitrary executable instructions. The actual schema should be split into strict discriminated per-action types in code. This sample is conceptual, not a copy-paste production schema.

## 5. Action result contract
Every executor call returns `status=completed|partially_completed|failed|cancelled|unverified`, `action_id`, `target_id`, `observed_state`, `error_code`, `retry_safe`, `undo_token?`, `user_message`, `evidence_timestamp`. Only `completed` may display a success claim. Timeout on send -> `unverified`, not failed; never retry automatically.

## 6. Risk matrix and authorization
- LOW: open/activate, scroll, switch, move/resize, focus, click benign navigation. Execute and show visual status.
- CONTENT: typed words, exact replacement, generated draft. Exact edits may apply with undo and changed-text highlight; substantial semantic rewrites previewed with accept/discard before replacing original.
- EXTERNAL/DESTRUCTIVE: send, delete content, submit, discard unsaved work, or risky OS action. Exact recipient/effect confirmation required. The MVP may explicitly decline delete operations even if a request is understood.
- No blind following of instructions embedded within emails/web pages: all external content is data, not system instructions.

## 7. Window management specification
**Target rules:** explicit app/title > verified active window > valid recent reference; if ambiguous identify candidates by title and voice number. Frame coordinates in screen points, respect visible bounds/safe areas. Standard tiles: left half/right half, equal halves; preserve minimum size. Relative sizing uses preconfigured small/large deltas, not LLM-generated coordinates. Track original frame and minimized state for undo.
**Operation procedure:** resolve -> inspect supported/settable AX attributes -> snapshot -> execute -> re-read -> compare tolerance -> log `completed` only on verification. Unsupported/full-screen/non-resizable/multi-screen request -> clarification or concise limitation. Primary display is guarantee; more displays may be experimental.
**Tests:** title collision; two windows same app; minimized; no window; off-screen; full-screen; unsaved modal; app loses focus; unexpected resize; three windows; app activation idempotency; undo when user manually moved window meanwhile.

## 8. Generic UI navigation
Read AX elements: role, label, help, enabled, focus, visible frame, app, window, hierarchy. Match deterministic labels/synonyms, then Bonsai may choose from a finite numbered candidate list. Numbered overlay numbers are scoped to a snapshot version, and must expire on layout changes. Click coordinates only derived from verified element frame; do not execute uncertain raw model coordinates. Scroll targeted scroll area; re-check focus and scroll completion. Query 'where am I' gives app/window/focus; 'what can I say' shows commands.
**Coverage ladder:** app integration -> AX element -> numbered AX overlay -> optional tested grid/local vision (P1/P2) -> clean unsupported message. Do not promise universal reachability for canvas, games, inaccessible embedded webviews.

## 9. Mail adapter
**Read/find:** input sender/subject/text/time; retrieve candidate identities by supported native scripting or AX; rank with verified metadata. If multiple meaningful matches, ask user. Bind `activeMessage` to stable ID/conversation and observe UI after opening.
**Compose/reply:** keep recipient identities separate from display strings; use original reply thread context; visible native Mail compose draft is source of truth. Confirm recipient list (To/Cc/Bcc where available), subject and content after populating. No unintended reply-all.
**Edit:** maintain draft model and old-version snapshot; apply exact changes only to verified text; preview semantic rewrites and preserve dates/names/numbers unless user instructs change. Detect external modifications before overwriting.
**Review/send:** render actual current draft; optionally read aloud. If user says send on a just-generated or unreviewed draft, present review-ready UI, ask 'Review or send?' but do not bypass exact-send confirmation. At final send, bind confirmation to actual current recipients/body/subject hash. `yes` authorizes once; afterward reconcile Mail send/queued state; no claim of delivery.
**Failures:** offline queued send, authentication prompts, missing compose window, wrong account, multiple Sarahs, attachment prompt, draft divergence, send timeout, permission rejected. On send uncertain, hold and investigate, never repeat.

## 10. Calendar adapter
EventKit reads accessible event calendars after explicit full calendar permission. Request event ranges in local time; normalize with source event time zones, account for daylight transitions and cross-midnight. Provide statuses BUSY, TENTATIVE, FREE_IN_ACCESSIBLE_CALENDARS, UNKNOWN, never universal 'free' if calendars not authorized or status ambiguous. Consider canceled/declined, out-of-office, all-day events and recurrence occurrences. Use EventKit for factual scheduling questions; UI launches/tiles Calendar and shows location, without inventing visual state. Do not create or modify events in MVP.

## 11. Voice session and dictation
Wake idle -> recognized wake -> listening window. Two user-controlled modes: wake-per-request and continuous session with configurable idle timeout. Session pause retains a minimal wake mechanism; explicit 'Flow, resume listening'. ASR finalized transcript is routed; interim transcript HUD only. In literal dictation: all ordinary speech inserted as text; standalone reserved 'Flow, stop dictation' exits; standalone 'Flow, stop' emergency interrupts; phrase embedded in longer utterance remains text. Protect against text generated during TTS playback by suppressing/ducking mic routing or validated echo cancellation. Recover microphone disconnect with visible banner and alternate access advisory.

## 12. Editing and version history
Supported actions: replace exact phrase, delete last sentence, insert prepend/append, punctuation, case, precise spelled characters, shorten/rephrase/formalize, read section, undo. Maintain immutable draft versions and `lastEditedRange`. If multiple occurrences of phrase: use exact current selection or ask. If semantic rewrite: use model proposal, compare factual slots (names, dates, times, numbers, URLs), require preview and accept. Any unexpected facts changed -> warning and user review. Edits never silently overwrite concurrent user changes. Undo available only while prior snapshot and target are compatible.

## 13. Recovery policy
Retries permitted for idempotent inspection, app activation, target refresh; e.g. max 2 attempts with bounded wait. Never automatically retry potentially duplicating send or irreversible commands. On exhausted recovery: concise one-line reason, at most 2 alternatives plus cancel; visual first, spoken when blocked. Every recovery choice voice-operable if microphone remains working. If both ASR and pointer path fail, report limit; avoid universal-access claim.
**Example:** message search 0 matches -> refresh once -> 'I couldn't find that email. Search by sender or go back to Inbox?' No wall of technical details.

## 14. Permission onboarding
Wizard: welcome, microphone, Accessibility, Apple Events as needed, EventKit, local server/model readiness, test wake/transcription, first task. Permissions persist per OS/app identity, but can be revoked. Flow cannot bypass macOS TCC; where pre-access permission is required, offer built-in Voice Control instruction or helper. Preflight verifies each capability and grades available features. Show actionable error rather than crashing.

## 15. Offline, network and security
Core API: `127.0.0.1` only; do not route email content through public cloud inference. Mail, Safari and account synchronization may require internet. Avoid logging audio or message contents. Exclude password and secure text fields from prompt context; redact hidden recipients when unnecessary. Local model requests bounded by maximum context length and minimal UI snapshots. Sandbox/test Apple Events privilege constraints on actual runtime. Include mock adapters for tests, clearly distinct from live demo.

## 16. Model runtime integration contract
PrismML Bonsai 2 required, choose 2B/4B/9B based on actual hardware testing. LM Studio is target server/UI; structured JSON endpoint is available in docs, but exact model compatibility MUST be validated. PrismML's own instructions warn special Bonsai packed formats and MLX loader combinations may be unsupported by bundled model engines. Keep `ModelProvider` interface compatible with LM Studio localhost and a PrismML local server contingency only if competition rules allow it; do not silently replace Bonsai with another model. Implement schema validator outside the model. Benchmark 30 intent prompts, 15 ambiguity prompts, 10 malformed-output tests on each feasible model.

## 17. Argmax integration contract
Argmax Pro real-time stable vs hypothesis streams: only finalized speech triggers actions; use dynamic vocabulary sparingly and only for compatible ASR model (Argmax docs note limitations for Whisper-family models). Speaker diarization != enrolled speaker identity; user voice lock is OPTIONAL until verified. Install/downloading required recognition models before offline demo. TTS local readback on request and confirmations; avoid continuous narration.

## 18. Acceptance scenarios (minimum 30)
| ID | Stimulus | Expected invariant |
|---|---|---|
| NAV-01 | Open already-open Mail | Activate, no unnecessary duplicate |
| NAV-02 | Click duplicate Reply labels | Disambiguate via message context |
| NAV-03 | Click number after UI change | Reject stale overlay |
| NAV-04 | Scroll disabled control | Return unavailable |
| NAV-05 | Target disappears before click | Re-inspect, never stale click |
| WIN-01 | Tile Mail + Calendar | Geometry verified and visible |
| WIN-02 | Make window a little wider | Deterministic increment |
| WIN-03 | Undo window move | Previous frame restored |
| WIN-04 | Two Notes windows | Clarification or title resolution |
| WIN-05 | Non-resizable window | Clean unsupported result |
| WIN-06 | Minimize then restore | Original window restored |
| MAIL-01 | Two matching Sarahs | Ask which before send |
| MAIL-02 | Find by sender+subject | Correct verified message |
| MAIL-03 | Reply to group | No silent reply-all |
| MAIL-04 | Compose via hybrid | Real draft visible, matching content |
| MAIL-05 | Change 3 to 3:30 | Exact intended change |
| MAIL-06 | Rephrase formal | Preview and preserve factual slots |
| MAIL-07 | Send without review | Enter review-ready state |
| MAIL-08 | Approve then recipient changes | Approval invalidated |
| MAIL-09 | Send result unknown | No duplicate retry |
| MAIL-10 | Offline Mail | No false delivered claim |
| CAL-01 | Event at 4pm | Busy/tentative correctly reported |
| CAL-02 | No calendar permission | UNKNOWN + remediation |
| CAL-03 | Overlapping tentative | Not represented as definitively busy |
| CAL-04 | Time zone crossing DST | Correct local time |
| VOI-01 | Dictate 'delete paragraph' | Insert literal words |
| VOI-02 | Standalone Flow stop dictation | Exit dictation |
| VOI-03 | Interrupt during plan | Stop at next safe checkpoint |
| VOI-04 | Other person speaking | No false strong authentication claim |
| ERR-01 | Bonsai malformed JSON | Reject, retry safe or fall back |
| ERR-02 | AX target stale | Never execute on old target |
| ERR-03 | Microphone disconnect | Error shown, no voice-only recovery promise |
| ERR-04 | First-run TCC denied | Explain without permission bypass |

## 19. Performance and test evidence
Measure P50/P95 from end-of-utterance to UI response, action execution and end-to-end completion; command count, spoken word count, corrections, false wake activations, accidental action rate, context resolution accuracy. Benchmarked target values (not confirmed): direct <1.5 s median, plan preview <3 s median, 0 unapproved external actions, 3/3 complete hands-free demo runs on frozen test Mac. Compare baseline against current Apple Voice Control under same fixtures.

## 20. Source references
PrismML: https://github.com/PrismML-Eng/Bonsai-demo ; https://prismml.com/news/bonsai-2-family
Argmax: https://app.argmaxinc.com/docs ; https://app.argmaxinc.com/docs/examples/custom-vocabulary ; https://app.argmaxinc.com/docs/examples/real-time-transcription
LM Studio: https://lmstudio.ai/docs/developer/openai-compat/structured-output
Source PRDs: Hands-Free Mac — Product Definition (2026-11-14); PRD: Hands-Free Computer Control, v1.0.
