# T-022 evidence — Apple Mail read and search (FlowMail)

**Date:** 2026-11-14 · **Branch:** `feature/mail-integration` · **Machine:** macOS 26.6.2, Mail 16.0 (1 account configured), Stage Manager on.

## Test data and privacy
- Live tests use only **`fixtures/mail/FlowTest.mbox`**: 5 synthetic messages from fictitious `@example.invalid` senders, including two different "Sarah"s. The user imported it via File → Import Mailboxes; it appears as *On My Mac › Import › FlowTest*.
- Every live query is scoped to that mailbox, and every returned reference is asserted to be local `…/FlowTest` with an `example.invalid` sender. No real message was opened or read by tests.
- Mail ignored the fixture's `Status: RO` header, so the imported messages started unread. Opening them let Mail mark them read; Flow wrote no flags (user decision).
- Side effects of manual probing (not tests):
  - Mail's main viewer was switched to the FlowTest mailbox, and Mail auto-selected one FlowTest message. Switching back was left to the user, because Mail would auto-select (and mark read) a real message.
  - One early probe printed the Message-ID of the real message selected at that moment. Later probes compared inside the script and printed booleans only.
- Automation consent: VS Code → Mail was approved by the user at the prompt. For Flow.app, `AEDeterminePermissionToAutomateTarget(ask: true)` returned "allowed" without showing a prompt, meaning a decision was already recorded. Check it in System Settings → Privacy & Security → Automation.

## Platform findings (gate G-04)
| Finding | Consequence |
|---|---|
| JXA search with `whose` on sender/subject is case-insensitive; bulk reads take ~60 ms for 5 messages | Used for search |
| `mailboxes.byName()` fails for nested local mailboxes (-1728); the app-level `mailboxes` list is flattened; `container()` throws at the top level | Mailboxes resolved by walking and comparing names/paths |
| JXA can't assign `selectedMessages`/`selectedMailboxes` (-1700); AppleScript switched the mailbox but didn't select the message | Open with `Mail.open(message)` (own window) |
| An opened window is titled "<subject> — <mailbox>"; header in an `AXTextArea`, body in an `AXWebArea` | Three-signal verification |
| `osascript` start-up plus a Mail round trip ≈ 0.1–0.25 s | Out-of-process scripting is fast enough |

## Results
`FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 swift test`: **254 passed, 0 failed.**

| Suite | Result |
|---|---|
| FlowMailTests: simulated backend, parser, formatter, wire decoding, real `osascript` runner | 36 passed |
| FlowMailTests: live Apple Mail (FlowTest mailbox) | 8 passed |
| FlowAXTests (incl. 9 live) | 59 passed |
| FlowWindowTests (incl. 3 live) | 48 passed |
| Track B suites (unchanged) | 103 passed |

### Acceptance tests (live)
| Acceptance test | Evidence |
|---|---|
| Find an email from a specified sender | "from Priya" → 1: Priya Patel — [FlowTest] Project budget review — Wed 11 Nov 16:45; Message-ID `flowtest-003@example.invalid`; ref `On My Mac/Import/FlowTest` |
| Search by subject | "launch checklist" → `flowtest-004`; "budget" → `flowtest-003` |
| Multiple matches → ask the user to choose | "from sarah" → `needs_clarification`: "3 messages match from 2 different senders (Sarah Chen <…>; Sarah Okafor <…>)"; nothing opened |
| Open the correct email in Mail | choose 2 → Sarah Okafor `flowtest-002`; scripting front window ✓, on-screen title ✓, body on screen ✓ → `completed` |
| Read its content | Body "Hey!\n\nAre you free for lunch on Friday? …" (92 chars); contains no headers, Message-ID or `X-Flow-Fixture`; "read it" re-reads without reopening |
| Clear no-results response | "No messages from “nobody-flowtest-zz” in mailbox “FlowTest”." |
| Reject stale references | Swapped Message-ID → `referenceChanged`; non-existent id → `messageGone`; non-existent mailbox → `messageGone`; nothing opened |
| Existing FlowWindow and FlowAX preserved | 48/48 and 59/59 |
| In Flow.app (typed Mail tab, driven via AX) | Clarification → choose 1 → `completed` (all three signals); "read it" → body in the Reading panel; no-results entry shown |

Opening an unread message (Diego, `flowtest-005`) added: "Mail marked it as read when it was opened (Mail's normal behaviour; Flow changed no flags)".

### Latency (per open, from result evidence)
- First optimized design: revalidate 840 ms + body 813 ms + open 2,994 ms + on-screen check 1,507 ms + read-state 558 ms.
- After merging round trips (revalidate + body; open + read state) and caching readiness for 60 s:
  - window already open: revalidate 532 ms + open 455 ms + check 387 ms;
  - new window: ~0.5 s + 0.9–1.8 s + 1.0–1.5 s.

## Fix to existing tests
The FlowAX Calculator live test failed once when Calculator was cold-launched: AX answers "cannot complete" until the window exists, and FlowAX reports that as `inaccessibleApp`. The test now waits for Calculator to become inspectable, and passes from a cold launch. No FlowAX source changed.

## Limitations
- **Default scope is Mail's unified Inbox.** Per the user's instruction, live tests ran only on the local FlowTest mailbox, so the unified-Inbox and account-mailbox paths (per-message mailbox resolution) are unit-tested but **not live-verified**.
- **No body-text search:** terms match subject or sender only. `content contains` is very slow on large mailboxes.
- **Open uses a separate message window,** not the main viewer's selection, because selection isn't scriptable here.
- **Opening can change read state** (Mail's behaviour). Flow reports it but doesn't prevent or undo it.
- **Body is Mail's plain-text rendering.** Attachments and images are dropped; HTML-only messages may read imperfectly; an empty body → `unsupported(contentUnavailable)`.
- **Search cost grows with mailbox size;** 30 s timeout → `timedOut` (retry-safe); limit 20 results, newest first, with the total reported.
- **Unread-detection is not a guarantee:** if Mail marks read after the check window, it isn't reported.
- **Automation consent is per app.** Flow.app's consent existed before it was requested (see above).
- **Misleading error during launch:** FlowAX reports `inaccessibleApp` for an app still launching (AX "cannot complete"). It should probably be `noWindow`/retry; proposed for FlowAX follow-up.
- **Not connected to voice or model output:** typed commands only (ADR 0004 proposals).

## Next recommended milestone
**T-024 Calendar EventKit read** (availability at a time: busy/tentative/free-in-accessible/unknown), completing the read side of the flagship journey ("Find Sarah's email about tomorrow" → "Do I have anything at four?").
Alternatively, **T-023 Mail compose/reply draft** (still no send), after agreeing ADR 0004 §1–3 with Track B.
