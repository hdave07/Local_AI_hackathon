# T-020 evidence — FlowWindow on real macOS windows

**Date:** 2026-11-14 · **Machine:** Apple Silicon, 8 GB, macOS 26.6.2 (25G83), one 1352×878 pt display
(usable AX frame `0,30 1352×769`), **Stage Manager on** (`com.apple.WindowManager GloballyEnabled = 1`).
**Permission:** Accessibility granted to the VS Code terminal that runs `swift test` / `flowctl`. Not granted to `build/Flow.app`.

## Reproduce
```
FLOW_LIVE_AX=1 swift test --filter FlowWindowTests        # unit + live milestone tests
.build/debug/flowctl "activate notes" "move notes left_half" "undo"
```

## Milestone: activate Notes → left half → verify → undo (real window)
Typed interface (`WindowCommandParser` → `WindowController` → `AXWindowBackend`), 3 consecutive live runs, all `completed`:

| Step | Result |
|---|---|
| `activate notes` | completed: Notes frontmost with a standard window at 205,151 858×647 |
| `move notes left_half` | completed: expected 0,30 676×769, AX re-read 0,30 676×768 (within 2 pt), window server bounds agree |
| `undo` | completed: AX re-read 205,151 858×647, window server bounds agree |

The original frame was also confirmed independently afterwards through CGWindowList (window 50127 at 205,151 858×647).

## Other live checks
| Command | Result |
|---|---|
| `minimize notes` → `restore notes` | completed / completed (after the fixes below) |
| `tile notes calendar` → `undo` | partially_completed: Calendar min width 908 pt + Notes min width 500 pt > 1352 pt, so the windows overlap by 56 pt; undo completed, both original frames restored exactly |
| Flow.app → Window Control tab → "activate notes" (driven via AX) | failed `accessibilityNotTrusted`, permission banner shown, no window touched |

## Platform findings
1. **Stage Manager hides other stages' windows from AX.** `kAXWindowsAttribute` returns no windows for an app outside the current stage, so activation must come first.
2. **A minimize sent during a stage transition is accepted then dropped.** `AXUIElementSetAttributeValue(AXMinimized, true)` returns success but nothing happens; one idempotent re-issue fixes it.
3. **A minimized window drops out of the AX window list** under Stage Manager while its element stays valid. Restore falls back to the window Flow itself minimized, re-validated by a fresh read.
4. **Window-server bounds lag AX** during stage transitions, so the CGWindowList cross-check polls (≤1.5 s) and is evidence only. AX re-reads are the verification.
5. **`NSRunningApplication.activate()` from a background process** did not bring an app forward under Stage Manager in a probe. `NSWorkspace.openApplication` (used for `activate`) did.
6. **App minimum widths:** Calendar 908 pt, Notes 500 pt. On a 1352 pt display Calendar can't take a true half, and the demo pair Mail+Calendar may not fit side by side.

## Signing identity and Accessibility persistence (2026-11-14)
**Before:** `codesign --sign -` (ad hoc). Designated requirement `cdhash H"fb10b4…"`, so the Accessibility grant applied to that one binary only.
**After:** `scripts/build_app.sh` signs with the Apple Development identity (team B2BY2NM48T). Designated requirement:
`identifier "dev.flow.FlowApp" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: … (B2BY2NM48T)" and certificate 1[field.1.2.840.113635.100.6.2.1]`.
The bundle ID `dev.flow.FlowApp` is unchanged.

Prerequisite fixed: the Apple Development certificate was "not valid" because the WWDR **G3** intermediate was missing (only the G1 intermediate, expired 2023-02-07, was present). AppleWWDRCAG3.cer was downloaded from apple.com over HTTPS, checked with `security verify-cert -L` (chains to Apple Root CA, valid 2020-02-19 to 2030-02-20, SHA-256 DC:F2:18:78:…:60:1F), and added to the login keychain. No trust settings were changed.

Persistence test, Flow.app driven through its own Window Control tab (activate notes → move notes left_half → undo):
| Build | cdhash | Grant action | In-app result |
|---|---|---|---|
| ad hoc (user-granted) | fb10b492… | granted by user | activate completed |
| A: Apple Development, debug | b2c1dc6c… | none | **not trusted** (old grant was hash-bound) |
| A (same process) | b2c1dc6c… | user re-granted once | activate completed |
| B: release rebuild | 4338481f… | none | activate, move, undo **all completed** |
| C: debug rebuild after a source change | 766d4d7c… | none | "Accessibility permission granted"; activate, move, undo **all completed** |

Note: one signing attempt failed intermittently with `errSecInternalComponent` (keychain key access); an immediate retry succeeded.
