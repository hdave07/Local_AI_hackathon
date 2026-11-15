# T-024 — Calendar read integration (EventKit)

Branch `feature/calendar-integration`, based on main `3d82d4a`. Design in [ADR 0008](../adr/0008-calendar-read.md).
Environment: macOS 26.6.2, Swift 6.4, time zone America/New_York.

## What works
- **Questions** (typed, or spoken in Flow.app's Voice tab) are answered from EventKit:
  - "What's on my calendar tomorrow?"
  - "Do I have anything at four?"
  - "Am I free Friday afternoon?"
  - "Is anything scheduled at 10 am on Tuesday?"
  - "Check whether I have anything at four tomorrow"
- **Statuses:** `busy` / `tentative` / `free_in_checked_calendars` / `unknown`.
  - All-day, overlapping, recurring, cancelled, marked-free and other-time-zone events are handled.
  - "Free" only ever means "free in the calendars checked", and the answer names those calendars.
  - Missing access (denied, restricted, write-only, not determined) or a missing calendar gives "I can't tell …", never "free".
- **Show a day:** "Show me tomorrow on my calendar" opens Calendar in day view on that day. Questions never open Calendar.
- **Structured result to the planner:** `Observation.availability(AvailabilityAnswer)`.
- **Executor log:** status and counts only, no event titles.
- **Read-only:** no code path creates, edits or deletes events.

## Fixture
`fixtures/calendar/FlowTest.ics` contains 11 synthetic events, imported into Calendar as the calendar **FlowTest** (iCloud). Calendar's import kept TENTATIVE, CANCELLED, TRANSP:TRANSPARENT, the RRULE and the Los Angeles TZID. The live check below confirms each of them.

## Tests
| Suite | Result |
|---|---|
| `swift test` (all non-live suites) | all pass, including FlowCalendarTests 25, FlowExecutorTests 45 (6 calendar integration), FlowSessionTests 21, FlowRoutingTests 74 |
| Live EventKit check: `scripts/run_calendar_livecheck.sh` | **15/15 pass** (2026-11-15) |
| Flow.app, typed through the Voice tab (same TaskSession → MacPlanExecutor path as speech) | 5/5 correct (below) |

One existing router test changed. "is anything booked at four tomorrow" is now routed by the deterministic calendar rule, which keeps "at four", so it no longer reaches the model guard. That test now uses a phrasing that does reach the guard, and a new test covers the rule.

### Live EventKit check (fixed "now" = Sat 14 Nov 2026 12:00, FlowTest only)
```
access: full_access
PASS "tomorrow at 4 pm"     → busy        Coffee with Sarah (4:00 PM–5:00 PM)
PASS "tomorrow at 10 am"    → tentative   Maybe: call with Priya (tentative)
PASS "tomorrow at 5 pm"     → free_in_checked_calendars (event ending at 5 doesn't overlap)
PASS "Monday at 11 am"      → busy        Team offsite (all day)
PASS "Tuesday at 3 pm"      → busy        Design review + Optional sync (tentative), overlapping
PASS "Tuesday at 5 pm"      → free_in_checked_calendars
PASS "Wednesday at 10 am"   → free_in_checked_calendars; Not counted: Cancelled standup (cancelled)
PASS "Wednesday at 4 pm"    → busy        Weekly 1:1 (recurrence, 1st)
PASS "November 25 at 4 pm"  → busy        Weekly 1:1 (recurrence, 2nd)
PASS "Thursday at noon"     → busy        West coast call (9 am Los Angeles = 12 PM New York)
PASS "Thursday at 9 am"     → free_in_checked_calendars
PASS "Friday afternoon"     → busy        Lunch with Diego; Not counted: Focus time (marked free)
PASS "Friday at 3 pm"       → free_in_checked_calendars; Not counted: Focus time (marked free)
PASS "November 21 at noon"  → free_in_checked_calendars; Not counted: Birthday reminder (all day, marked free)
PASS day listing Tuesday    → [Design review, Optional sync]
RESULT 15/15 passed
```

### Flow.app (real clock, Sun 15 Nov 2026 ~00:10, scope "FlowTest only")
| Command | Flow's answer | Executor log |
|---|---|---|
| Do I have anything at four? | In your FlowTest calendar, you're busy Sun 15 Nov at 4:00 PM: [FlowTest] Coffee with Sarah (4:00 PM–5:00 PM). (I assumed you meant today; I took that as 4:00 PM.) | `availability: busy … calendars checked: 1` |
| What's on my calendar tomorrow? | In your FlowTest calendar, you're busy tomorrow (Mon 16 Nov): [FlowTest] Team offsite (all day). | busy, 1 overlapping |
| Am I free Friday afternoon? | …busy Fri 20 Nov in the afternoon (12:00 PM–5:00 PM): Lunch with Diego (1:00 PM–2:00 PM). Not counted: Focus time (3:00 PM–4:00 PM, marked free). | busy, 2 overlapping |
| Is anything scheduled at 5 pm today? | Nothing is scheduled today (Sun 15 Nov) at 5:00 PM in your FlowTest calendar, so you look free. | free_in_checked_calendars |
| Show me tomorrow on my calendar | Showing Mon 16 Nov in Calendar. | `show_calendar → completed · Calendar: Mon 16 Nov` |

For "Show me tomorrow", Calendar's own accessibility tree was read independently afterwards. It showed the **Day** view selected, **16, Monday, November** selected, and "[FlowTest] Team offsite. Monday, November 16, 2026, All-Day" on screen.

Flow.app got calendar access through macOS's normal prompt for Flow. It got Calendar automation consent the same way.

## Limitations
- **Command-line processes can't get calendar access.** `swift test` and `flowctl` can't obtain it (no prompt; `granted: false`), so the live EventKit check runs as the small signed bundle `build/FlowCalendarLiveCheck.app`. Its first run asks for calendar access.
- **Show-day verification is script-level.** Flow treats Calendar's scripting reply as confirmation. It doesn't re-read Calendar's window through AX; that was done manually for the evidence above.
- **The voice path was exercised by typing into the Voice tab.** That is the same TaskSession/executor path the spoken path uses. The spoken acceptance ("Do I have anything at four tomorrow?") still needs a run by the user at the mic.
- **"What's on my calendar tomorrow?"** is answered as an availability check for the whole day. It lists every event, but phrases it as "you're busy tomorrow: …".
- **Time parsing is rule-based.** Phrases it can't place get "Which day or time should I check?". am/pm is inferred (1–6 PM, 7–11 AM), and the inference is said aloud.
- **Scope:** `FLOW_CALENDAR_SCOPE=all` (all authorized calendars) is implemented and unit-tested, but wasn't run live, so that private calendars stay unread.
- Events where the user is an attendee use EventKit's `isCurrentUser` participant. Delegated or shared calendars weren't tested.

## Fix after the first spoken session (2026-11-15)
**What happened at the mic:**
- "No, I mean like do I have anything at four?" got "Which calendar day or time are you asking about?" from the model.
- Then "Uh, today." got "What day are you referring to today?"

**Causes:**
1. The cleaner didn't strip the "I mean / like" lead-ins, so the calendar rule missed the phrase and the model answered.
2. The model's question wasn't recorded as a pending calendar question, so "today" arrived with no context.

**Fixes:**
- "I mean", "I meant", "like" and "yeah" are now stripped as openers.
- "Don't have anything at …" (ASR dropping "Do I") routes as a calendar question.
- New `PendingQuestion.calendarTime`, set whenever Flow asks "Which day or time should I check?", including when the model's own clarification sounds like a calendar question. A bare time answers it.
- New `ConversationContext.calendarTopic`. The PlanRunner sets it from a verified availability answer, so a bare time right after a calendar answer ("What about tomorrow?", "and at five?") continues it. After any other action, a bare day isn't treated as a calendar question.

**Re-check in Flow.app (typed in the Voice tab):**
- "No, I mean like do I have anything at four?" → busy, Coffee with Sarah.
- "What about tomorrow?" → Team offsite (all day).
- "Do I have anything" → "Which day or time should I check?"
- "Uh, today." → today's two events.

**Tests:** new router tests (`CalendarFollowUpTests`) and a TaskSession + executor test (`spokenFollowUpsReachTheCalendar`). The full suite passes.
