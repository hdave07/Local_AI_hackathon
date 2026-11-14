# ADR 0001 — Window control types and proposed FlowCore changes

**Status:** Proposed (needs Track B agreement) · **Date:** 2026-11-14 · **Owner:** Track A (`feature/mac-control`)

## Context
Track A added the `FlowWindow` module. Shared contracts in `FlowCore` are co-owned with Track B, so this branch makes **no FlowCore changes**. FlowWindow only *reads* existing FlowCore types: `KnownApp`, `WindowTarget`, `WindowPosition`, `ResizeChange`, `FlowAction`.

## Decision (this branch)
Track-A-local types live in `FlowWindow` until both tracks agree to promote them:

| FlowWindow type | Purpose | Spec reference |
|---|---|---|
| `WindowCommand` | typed window/app commands; `init?(FlowAction)` bridges from the classifier | 02 §4, §7 |
| `WindowSelector` | `WindowTarget` + optional window title for same-app disambiguation | 02 §7, WIN-04 |
| `ActionStatus` | `completed / partially_completed / failed / unverified` **+ `unsupported`** | 02 §5 |
| `WindowActionResult` | §5 result shape: action id, targets, before/expected/observed frames, error, undo token, retry-safe, message, timestamp | 02 §5 |
| `WindowRef` | window identity: session `WindowID` + bundle ID + title | 03 §3 `AppWindowRef` |

## Proposed FlowCore changes (for Track B review)
1. **Promote `ActionStatus` (with `unsupported`) and a generic `ActionResult` into FlowCore** once the planner/executor (T-026) consumes results from several adapters. Spec 02 §5 lists no `unsupported` status, but the Track A brief requires typed unsupported results and spec 02 §7 asks for "clarification or concise limitation" for non-resizable/full-screen windows.
2. **Add `minimize_window` and `restore_window` to `ActionType`/`FlowAction`.** PRD D-017 and acceptance test WIN-06 require minimize/restore, but spec 02 §4's action allowlist has no such action, so the classifier can't express them yet. FlowWindow already implements them (`WindowCommand.minimize/restore`).
3. **Optional title on `WindowTarget`** (e.g. `.titled(KnownApp, String)`) so a spoken "move the Groceries note window left" can disambiguate same-app windows without a clarification round-trip.
4. **`AppWindowRef`** (plan 03 §3) should carry `pid` and a snapshot epoch. FlowWindow re-resolves windows on every action and re-validates its window ID against live AX state, so no epoch is needed yet.

## Consequences
- The classifier→window bridge works today for `activate_app`, `move_window`, `resize_window` and `tile_windows` through `WindowCommand(FlowAction)`. Nothing runs model output automatically; executing it needs the planner/confirmation flow.
- Once (1) is adopted, `WindowActionResult` becomes a FlowWindow specialization of the shared result.
