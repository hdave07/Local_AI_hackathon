# T-021 evidence — Generic macOS UI navigation (FlowAX)

**Date:** 2026-11-14 · **Branch:** `feature/ui-navigation` · **Machine:** Apple Silicon, 8 GB, macOS 26.6.2, one 1352×878 pt display, Stage Manager on.
**Permission:** Accessibility granted to the VS Code terminal (tests, `flowctl`) and to Flow.app (stable Apple Development signature; unchanged identity, no re-grant needed).

## What was built
- **Inspection:** `AXUIBackend.snapshot` walks the target app's focused (or main) window.
  - Records role/subrole, title, description, value (never for secure fields), placeholder, identifier, enabled/focused/selected, frame, AX actions, and settable focus/selection.
  - Visibility uses the window, ancestor scroll-area clipping and on-screen bounds.
  - Labels are inherited from `AXTitleUIElement`, descendant text (rows, cells, buttons) or child content (unlabeled scroll areas).
  - Limits: 2,000 elements, depth 40, 2 s; truncation is flagged.
- **Resolution:** deterministic tiers (exact > prefix > all words > substring), role words ("button", "field", "row", "sidebar"…), ordinals ("second", "last"), number words and a few synonyms ("seven" → 7, "plus" → Add), and container de-duplication.
  - Several equally good matches → clarification with numbers.
  - Substring-only matches → "Did you mean…?" confirmation.
- **Actions:** `AXPress`; `AXSelected` for rows/cells; `AXFocused` for fields (clicking a field focuses it); scrolling in this order: `AXScroll…ByPage` → scroll-bar value by one estimated page → scroll-bar page part.
- **Revalidation before every action:** re-read the same AX element and refuse if it's gone, has a different role, label or identifier, moved more than 2 pt, or is disabled. Numbers are refused if the actionable layout changed since they were shown (text-only changes are allowed).
- **Verification:**
  - Press → re-observe the window: content, layout or title change → `completed` (with a description of what changed), otherwise `unverified`.
  - Select → `AXSelected` re-read.
  - Focus → the app's focused UI element is the target.
  - Scroll → scroll-bar value or content movement *in the requested direction*. The wrong direction is `failed`; no movement is `unverified`; at the end is `failed(atScrollLimit)` with no action taken.
- **Numbered overlay:** a non-activating, click-through `NSPanel` at status-bar level, with orange outlines and numbered badges. Badges are AX static texts labelled "n: target". Numbers are single-use, expire after 60 s, and are tied to one snapshot's layout.
- **Interfaces:** Flow.app "UI Navigation" tab (typed commands, numbered-target buttons, result log); `flowctl` navigation commands; `NavCommand(FlowAction)` bridge (not wired to model output).

## Test results (all run 2026-11-14)
`swift build --product flow-nav-fixture && FLOW_LIVE_AX=1 swift test`

| Suite | Result |
|---|---|
| FlowAXTests: unit (simulated backend) | 50 passed |
| FlowAXTests: live (real apps) | 9 passed |
| FlowWindowTests (incl. 3 live) | 48 passed |
| Track B suites (FlowLLM, FlowAudio, FlowArgmax, FlowBench, FlowCore) | 103 passed, unmodified |

### Acceptance tests (live, real Accessibility)
| Acceptance test | Evidence |
|---|---|
| Locate and activate a named control | Fixture: "the Save button" → completed; status label re-read "Status: Save pressed". Calculator: "seven", "plus", "the 3 button", "equals" → each completed, display "10". |
| Focus a text field | "the search field" → completed; the fixture's focused UI element re-read is the `search` field. |
| Scroll a supported view | Fixture (AppKit): scroll-bar value 0.000 → 0.186 → … → 1.000; "scroll down" at bottom → `atScrollLimit`. System Settings (SwiftUI) sidebar: 0.967 → 0.000 via the native page action. |
| Show numbered targets and select one | Fixture: "show numbers for reply" → numbers map to identifiers [replyA, replyB]; choose 2 → "Reply B pressed". Flow.app on Calculator: 25 real overlay badges read back through AX at each element's corner; "choose 10" → "7" button → display "7". |
| Clarification instead of clicking indistinguishable elements | "click reply" → `needs_clarification` "There are 2 identical “Reply” buttons"; status still "ready". |
| Refuse stale or changed targets | Numbers after a layout shift → `staleNumbers`, nothing pressed. Planner-held element refs: removed → `targetGone`; renamed → `targetChanged("“Volatile” is now “Changed”")`; moved → `targetChanged("moved from 222,288 to 302,288")`. |
| Existing window-control tests still pass | FlowWindowTests 48/48, including live Notes move/undo and minimize/restore. |

## Bugs found and fixed during live testing
1. AppKit `NSScrollView` lists `AXScrollDownByPage` but returns `kAXErrorActionUnsupported`, so a scroll-bar fallback was added.
2. Pressing the scroll bar's page part sometimes scrolled the **wrong way**, and verification initially accepted any movement. It now requires the requested direction, and paging prefers the scroll-bar value.
3. SwiftUI elements don't support `AXWindow`. Revalidation had treated that as "gone"; only `kAXErrorInvalidUIElement` counts now.
4. "the search field" treated "search" as part of the role word and asked which of 3 fields; "search" is now kept as a query word.
5. Clicking a numbered text field failed as "not pressable"; clicking a field now focuses it.
6. A disabled button was offered as a numbered target; disabled elements are now resolvable (to report "disabled") but not numbered.
7. Moving controls didn't count as an observable change; layout changes now do.

## Limitations
- **Scope:** only the target app's focused/main window. Menu bar, pop-up menus and popovers outside the window are not inspected, so Calculator's "Mode" menu press was honestly `unverified`.
- **AX-only actions:** no synthesized mouse events. Controls without `AXPress`/`AXSelected`/settable focus are `unsupported`. Apps with no AX content (canvases, games, some web views) → `inaccessibleApp`.
- **Verification is observational:** a press with no visible AX change is `unverified`, even if it worked (e.g. All Clear on an already-cleared display).
- **Overlay:** primary display only; multi-display untested.
- **Numbers are conservative:** any change to actionable labels or frames invalidates them, e.g. Calculator relabels All Clear → Clear after any digit.
- **Page-size estimate:** AppKit overlay scroll bars change thumb geometry, so "one page" shrank from 0.186 to 0.066 on later pages. Direction and verification are unaffected.
- **Labels:** inheritance is heuristic (first descendant text). Unlabeled controls are reachable by number only. The synonym table is small and English-only.
- **Stage Manager:** the target app must be brought forward to be visible to AX; macOS may refuse to activate unbundled processes from the background.
- **Not connected to model output:** typed commands only; voice "choose N" needs Track B routing (ADR 0003 §2).
- **Text entry** (`insert_text`/`replace_text`) is out of scope (T-025).

## Next recommended milestone
**T-022 Mail read/search on top of FlowAX:** find and open a message by sender and subject, bind the active message, and disambiguate "two Sarahs" with the numbered overlay. In parallel, agree ADR 0003 §1–2 with Track B, so "show numbers" and "choose N" route deterministically from voice and the planner (T-026) can call `UINavigator` with validated actions.
