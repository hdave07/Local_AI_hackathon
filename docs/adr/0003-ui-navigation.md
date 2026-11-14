# ADR 0003 — Generic UI navigation (FlowAX) interfaces

**Status:** Proposed (needs Track B agreement for the FlowCore items) · **Date:** 2026-11-14 · **Owner:** Track A (`feature/ui-navigation`)

## Context
Phase 2 milestone 1 (plan 03 T-021, spec 02 §8) adds generic UI navigation. Shared FlowCore contracts are co-owned, so this branch makes **no FlowCore changes**. FlowAX only reads FlowCore's `FlowAction` (`click_element`, `focus`, `scroll`) and `ScrollDirection`, and reuses FlowWindow's `AppHandle`, `AccessibilityPermission` and frontmost-app tracking.

## Decision (this branch)
New Track A module **`FlowAX`** (spec 02 §2 `UIInspector` + `TargetResolver`, plan 03 `FlowAX/`):

| Type | Role |
|---|---|
| `UIBackend` / `AXUIBackend` | Inspection (`snapshot`, non-retaining `observe`), fresh re-read (`refresh`), AX actions: press, focus, select, scroll. Public AX API only. |
| `UISnapshot`, `UIElementInfo`, `ElementID(epoch, index)` | Sendable, AX-free element descriptions scoped to a snapshot epoch. Secure-field values are never read. |
| `TargetReference`, `TargetResolver` | Deterministic resolution: fixed match tiers, role hints, ordinals, small synonym table, container de-duplication. Returns `unique / ambiguous / lowConfidence / notFound`. Never breaks ties by guessing. |
| `UINavigator` | Resolve → clarify, or revalidate → act → verify. Holds the active numbered set. `perform(_:on:in:)` is the planner entry point for previously inspected elements. |
| `NavCommand`, `NavCommandParser` | Typed test interface (Flow.app "UI Navigation" tab, `flowctl`). `NavCommand(FlowAction)` bridges classifier actions but is **not** wired to model output. |
| `NavigationResult`, `NavigationStatus` | Spec 02 §5 statuses + `needs_clarification`. |
| `OverlayPresenting` / `ScreenOverlay` | Click-through, non-activating numbered overlay. Badges are AX elements labelled `"<n>: <target>"`. |

## Proposed FlowCore changes (for Track B review)
1. **Shared result status.** Extend ADR 0001 §1: a FlowCore `ActionStatus` should include `needs_clarification` (or a separate `Clarification` payload), so the planner handles window and navigation results uniformly.
2. **Numbered-choice and overlay commands in the deterministic router.** "show numbers", "hide numbers" and "choose/number N" are control-like, latency-sensitive and must not depend on the model. Proposal: add them to `DeterministicRouter` (FlowCore) as control commands, or add `FlowAction.selectNumber(Int)` / `.showNumbers(String?)`. Either way, numbers reach FlowAX as `NavCommand.choose(n)`.
3. **`click_element` / `focus` label semantics.** FlowAX parses the label as a spoken reference (articles, role words, ordinals). Track B can keep emitting raw phrases ("the second Reply button"); no schema change is needed.
4. **App scope on navigation actions (optional).** Today a model action targets the frontmost app. "click Save in Notes" would need an optional app field on `click_element`/`focus`. Not required for this milestone.

## Consequences
- The future executor calls `UINavigator.perform(NavCommand)` or `perform(intent, on: element, in: app)`. Both always revalidate against live AX.
- Model output is still not connected to execution. Wiring needs the planner/confirmation policy (T-026) and ADR 0002's `IntentSink`.
