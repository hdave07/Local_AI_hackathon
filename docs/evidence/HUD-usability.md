# Floating HUD, app/window control and usability — evidence

Branch `feature/floating-hud-and-usability` (from `origin/main` 6c02c26). Design: [ADR 0011](../adr/0011-floating-hud-and-app-control.md).
Run overnight on 2026-11-15 without the user present (see **Assumptions**). Nothing was sent, deleted or drafted in Mail. Only FlowTest fixtures and Flow's own test app were used.

## What works
- **The floating HUD stays visible over other apps without taking focus.** It shows:
  - listening / hearing / working / speaking / waiting / error state;
  - "You said …";
  - the open question with numbered choices;
  - verified, failed or stopped outcomes;
  - a hint of what to say next;
  - recent items.
- **HUD controls:**
  - collapse to a status pill (still shows state, plus a "?" badge when an answer is needed);
  - hide (a new question brings it back);
  - text size;
  - drag to reposition (remembered, kept on screen).
- **Voice app/window control:** open, switch, bring to front, go back, minimize, restore, close a window (never quit), list open windows.
- **Questions survive quick app commands.** "Switch to Calendar" while Flow waits for "which Sarah?" runs, and the question stays open. "Switch to Mail" while Flow asks what a reply should say is no longer typed into the reply.
- **Spoken feedback is wired into Flow.app.** What it says is what the HUD shows.

## Automated tests (all simulated)
| Suite | Tests | Covers |
|---|---|---|
| `FlowHUDTests` | 19 | state transitions; choices and question; confirmation shown but never approvable by the HUD; a new question re-shows a hidden HUD; hide doesn't stop the task; speaking + expected response; failures/cancel labels; mic error; confirmation timeout; echo ignored; bounded, truncated retention; placement (default corner, second display, clamping, unplugged display, growth, coverage under 6%, tiny screen) |
| `FlowRoutingTests` — AppWindowRoutingTests | 8 (+19 phrasings) | every acceptance phrase routes deterministically (the model is never called); fillers and corrections; restore/bring back via context; bare "go back"; quitting refused; unknown close explained; draft "close" unchanged; window actions not model-emittable |
| `FlowWindowTests` — CloseWindowTests | 7 | close verified, app keeps running, no undo; unsaved-changes sheet left alone; window that won't close → unverified; active window = focused window; several windows → asks; app not running / no window; FlowAction bridging |
| `FlowExecutorTests` — AppControlScenarioTests | 12 | **Scenario A** (open → switch → go back → minimize → restore); bare go back; list windows read-only; close Notes ≠ quit; save sheet; quit refused; missing and ambiguous windows; **Scenario B** (choices survive Mail frontmost and "switch to Calendar", then "the first one"); router question survives "switch to Mail"; **Scenario C** (everything needed to answer is in the HUD state); **Scenario D** (send needs a spoken yes; switching apps abandons the confirmation; delete declined); stop clears the question |
| Full `swift test` | all suites | pass (exit 0) |

## Live verification on this Mac (macOS 26.6.2, one display, Stage Manager on)
Flow.app was rebuilt and launched with `FLOW_SPOKEN_FEEDBACK=off`, so it wouldn't talk overnight. Commands were typed into the Voice tab through Accessibility without activating Flow. The frontmost app was checked with fresh `lsappinfo` queries, and the HUD's content was read through Accessibility.

- **The HUD is a separate window at window layer 3 (floating):** 340×64 at the top right, about 2% of the screen.
- **It stays on screen with Notes, Calendar and Mail each frontmost.**
- **Background commands never made Flow frontmost.** Calendar stayed frontmost through a background command.
- **Scenario A, live on real Notes and Calendar windows:** all five steps were verified by the executor (`activate_app` ×3, `minimize_window`, `restore_window` → completed). The HUD showed "You said: …" and "Done: …" for each.
- **Scenario B, live on the FlowTest mailbox:**
  1. "Find Sarah's email" made Mail frontmost. The HUD showed *Waiting for your choice — Which one?*, three labelled choice buttons, and the hint.
  2. "Switch to Calendar" made Calendar frontmost, and the HUD still showed the choices.
  3. "The first one" opened the FlowTest message: *Done: Open Mail → Find "Sarah's email" in Mail.*
- **HUD controls pressed through Accessibility kept Notes frontmost:**
  - Collapse → 147×34 pill.
  - Expand → back to 340×64 at the same spot.
  - Hide → panel off screen; the next question → panel back on screen.
  - "cancel" cleared a question.
- **Opt-in live suites:**
  - `FLOW_LIVE_AX`: LiveWindowTests 3 ✓; new LiveCloseWindowTests ✓ (real AX close button, on Flow's own fixture app); FlowAXTests ✓ (`systemSettingsSidebarScrollsReadOnly` failed once with "System Settings has no window", then passed on retry; FlowAX is unchanged on this branch).
  - `FLOW_LIVE_AX` + `FLOW_LIVE_MAIL`: LiveExecutorTests 3 ✓.
  - `FLOW_LIVE_MAIL`: LiveMailTests 8 ✓ and LiveSendScriptTests 1 ✓.
  - Calendar live check: 15/15 ✓.
- **Not run:** `LiveReplyDraftTests` and `LiveDraftEditingTests`. They create and delete drafts in the user's real Mail and shouldn't run unattended.

## Assumptions (the user was asleep; each is easy to change)
1. **"Close Notes" closes Notes' window, not the app.** Quit and force quit are always declined. The spec says to distinguish the two and never quit without a separately approved design.
2. **Closing a window counts as low risk.** Flow never answers an app's "save changes?" sheet; it reports that the app is asking.
3. **A new question re-shows a hidden HUD and expands a collapsed one,** so questions can't be missed. Hiding is otherwise respected.
4. **A spoken send confirmation is still abandoned by "switch to …"** (ADR 0010 behavior). Only plan choices and router questions survive quick app commands. This keeps the send path conservative.
5. **"Restore it" / "that window"** means the window Flow last acted on; "this window" means the window in front. "it" with no history is not guessed.
6. **Bare "go back"** means the previously active app (tracked from Flow's own verified actions, not from the user's clicks).
7. **The HUD offers clickable numbered choices, Cancel, and "No, don't send", but no approve or send button.** A send stays voice-only and explicit.
8. **Spoken feedback is on by default in Flow.app** (it was a completed milestone, not yet wired in). `FLOW_SPOKEN_FEEDBACK=off` turns it off.
9. **Default HUD position** is the top-right of the primary display. The position is remembered in `UserDefaults` (per-Mac convenience only).
10. **"Show me my open windows"** lists only apps Flow can control (Mail, Calendar, Notes, Finder, Safari), up to 4 windows each, with titles truncated to 40 characters.
11. **The four new window actions are deterministic-only** (not offered to the language model), like `edit_text`.

## Limitations / not verified
- **Spoken feedback was not exercised audibly tonight** (launched with `FLOW_SPOKEN_FEEDBACK=off`). HUD and speech consistency is covered by unit and voice-path tests (`VoiceSendTests`, `FlowSpeechTests`).
- **Only one display was available.** Multi-monitor and screen-change behavior is covered by `HUDPlacement` unit tests, not live.
- **Full-screen apps and other Spaces** use the standard panel flags (`canJoinAllSpaces`, `fullScreenAuxiliary`) but weren't tried live.
- **Clicks were simulated with Accessibility presses**, not physical mouse clicks. A physical click on a non-activating panel shouldn't activate Flow, but that wasn't observed live.
- **Routine successes aren't narrated.** "Done: Close Notes." is shown; the executor's "Notes is still open" detail is only in the log.
- **`PendingQuestion.app`** ("Which app?") is answered by an app command rather than preserved; that is intended.
