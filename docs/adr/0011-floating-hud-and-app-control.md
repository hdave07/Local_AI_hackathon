# ADR 0011 — Floating HUD, voice app/window control, persistent questions

**Status:** Proposed · **Date:** 2026-11-15 · **Branch:** `feature/floating-hud-and-usability`

## Context
Flow's Voice tab goes behind other apps, so users can't see:
- the listening state;
- what was heard;
- clarifying questions or numbered choices.

That breaks hands-free use. Common app and window commands were also missing:
- minimize, restore and close by voice;
- "go back" to the previous app;
- listing open windows.

Two problems in conversations:
- Switching apps during a conversation dropped the open question.
- A quick command could even be taken as the answer: "switch to Mail" became the text of a reply.

## Decision 1 — The HUD is a projection of existing events (no new state store)

**Module `FlowHUD` (pure, unit-tested)**
- **`HUDState`** reduces two existing event streams:
  - `VoiceSessionCoordinator`'s `CoordinatorEvent`;
  - `SpokenFeedback`'s `FeedbackEvent`.

  What Flow is waiting for comes only from the coordinator's `TaskPhase`. That phase mirrors the planner's `RunState` and the router's pending question.
- **Activity** is one of: idle / listening / hearing / processing / speaking / awaiting choice / awaiting confirmation / awaiting answer / error.
- **Contents:**
  - the last finalized utterance;
  - the open question with numbered choices;
  - the outcome (verified / not done / stopped);
  - a "what you can say next" hint;
  - up to 4 recent entries.
- **Privacy:**
  - Outcomes are truncated (220 characters) and recent entries more so (80).
  - Nothing is logged.
  - A confirmation's full text is shown only while it is open.
- **A new question (choice, confirmation, router question) re-shows and expands a hidden or collapsed HUD.** A question can't be missed; the user can collapse it again.
- **`HUDPlacement`:**
  - defaults to the top-right of the primary display;
  - remembers where it was dragged, per display;
  - keeps the HUD inside a display's visible frame, moving it to the nearest display if one is unplugged;
  - hangs the HUD from its top edge as it grows.

**Flow.app**
- `HUDPanelController` uses an `NSPanel` subclass that never becomes key or main:
  - `.nonactivatingPanel` style;
  - `.floating` level;
  - `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`;
  - `hidesOnDeactivate = false`;
  - shown with `orderFrontRegardless`.

  It never activates Flow, so keyboard focus and Accessibility targets stay with the user's app.
- `VoiceViewModel` already consumes the coordinator stream; it forwards each event to `HUDModel`. Spoken feedback's events go to the same model.
- **Controls:**
  - start/stop listening;
  - collapse/expand;
  - hide (the task keeps going);
  - text size (1.0×, 1.25×, 1.5×);
  - clickable numbered choices (submitted exactly like saying the number);
  - Cancel for a question;
  - "No, don't send" for a send confirmation.
- **There is no approve or send button.** A send still needs a spoken, explicit yes (ADR 0010).
- **Visibility:** the menu item HUD › Show (⌥⌘H) brings it back. `FLOW_HUD=off` disables it.

## Decision 2 — Wire spoken feedback into Flow.app (ADR 0008 decision 3)
- `SpokenFeedback(output: SystemSpeechOutput())` is attached to the coordinator.
- Its events feed the HUD, so what is spoken is what the HUD shows.
- `FLOW_SPOKEN_FEEDBACK=off` disables it.

## Decision 3 — Window actions by voice (deterministic only)
- **New FlowCore actions:** `minimize_window`, `restore_window`, `close_window`, `list_windows`.
  - They are excluded from the model's schema (`ActionType.deterministicOnly`), and the validator and guard refuse them from model output.
  - Risk level is low.
- **FlowWindow:**
  - `WindowCommand.close`;
  - `WindowBackend.close` (presses the window's AX close button);
  - `hasSheet`.
- **Closing:**
  - is verified (the window leaves the app's list);
  - never quits the app;
  - is never undone.
  - If the app asks "save changes?", Flow stops and reports `partially_completed`. The sheet is the user's decision; Flow never presses "Don't Save".
- **Quit, force quit, kill and shut down are always declined**, with a pointer to closing a window instead.
- **Routing (`Rules.windowControl`, before the unsupported-verb rule):**
  - "close Notes / this window";
  - "minimize (this window)";
  - "restore it / that window / the Notes window";
  - "bring it back";
  - "go back (to Notes)";
  - "bring Calendar to the front";
  - "show me my open windows" / "what windows are open".
- **Pronouns:**
  - "it" / "that window" mean the window Flow last acted on (`selectedWindow`, else `activeApp`). With neither, Flow doesn't guess.
  - "this window" means the active window.
  - Bare "go back" uses the new `ConversationContext.previousApp`; with no history, Flow asks which app.
- **Listing windows** is read-only: titles of Mail, Calendar, Notes, Finder and Safari windows, up to 4 per app.

## Decision 4 — Quick app commands keep the open question
- **While Flow waits for a choice** (`awaitingChoice`), a one-step app or window command runs on a separate `PlanRunner` with the same executor and shared store. The paused plan is untouched, and Flow says "Still waiting. <question>". The HUD keeps showing the choices.
- **While a router question is open** ("What should the reply say?"), `Rules.answer` refuses to treat a quick app command as the answer. The command runs and the question stays open; the new `ConversationContext.pendingPrompt` repeats it. ("Which app?" is the exception: "open Notes" answers it.)
- **A send confirmation is still abandoned** by any non-answer, unchanged from ADR 0010. Switching apps never approves anything.

## Consequences
- **No new conversation store:** the HUD reads events, and its controls call the coordinator's existing `submit` / `startListening` / `stopListening` and the feedback's `stopSpeaking`.
- **FlowCore gains four actions.** Exhaustive switches were updated: validator, guard, benchmark, plan capability, mock executor, context.
