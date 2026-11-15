# ADR 0008 — Calendar read integration (FlowCalendar)

**Status:** Proposed · **Date:** 2026-11-15 · **Owner:** Tracks A+B (`feature/calendar-integration`)

## Context
T-024 (spec 02 §10) lets the user ask about their calendar by typed command or voice and get a
verified answer from EventKit. The milestone is read-only.

## Decisions
1. **EventKit through a `CalendarStore` protocol** (`access`, `requestAccess`, `calendars`, `events`).
   - There are no create, edit or delete operations.
   - `EventKitStore` uses `requestFullAccessToEvents`. The macOS consent prompt is never bypassed.
   - Recurring events are expanded by `predicateForEvents`.
2. **Never "free" without evidence.**
   - Statuses are `busy`, `tentative`, `free_in_checked_calendars` and `unknown`.
   - The status is `unknown` when access isn't `fullAccess` (denied, restricted, write-only, not determined) or when there are no calendars to check. Errors answer "I can't tell …".
   - Cancelled, declined and marked-free events never block. Busy outranks tentative. A tentative status or availability, or a tentative or pending response, counts as tentative.
3. **Calendar scope is configurable.**
   - `.named(["FlowTest"])` is the default and the only scope used in tests.
   - `.allAuthorized` is selected in Flow.app with `FLOW_CALENDAR_SCOPE=all`.
   - Every answer names the calendars it checked ("In your FlowTest calendar, …"). A missing named calendar is an error, never "free".
4. **Time expressions are parsed deterministically** (`TimeExpressionParser`), with assumptions stated aloud.
   - Supported: day words, weekdays, month/day, parts of the day, ranges, digits and number words (only with a cue such as "at" or "o'clock").
   - When no day is given, "I assumed you meant today". Without am/pm, 1–6 → PM and 7–11 → AM, and the answer says "I took that as 4:00 PM".
   - A spoken moment covers 30 minutes. Day arithmetic goes through `Calendar` in the local time zone, so it's DST-safe.
5. **Showing a day is a separate, optional action.**
   - New FlowCore action `show_calendar(dateExpression)`, risk low, capability `interact`.
   - The router uses it only for "show/open … on my calendar" phrasings. Questions are answered, never shown.
   - `JXACalendarViewer` only switches Calendar to day view on that day.
6. **Structured results to the planner.**
   - New `Observation.availability(AvailabilityAnswer)` (FlowRouting `AvailabilityAnswer`: status, interval, events with effect, calendarsChecked, answer).
   - `PlanRunner` verifies `query_calendar` with it and speaks `answer`.
7. **Privacy.**
   - Event titles appear only in the answer shown or spoken to the user.
   - The executor log uses `CalendarReport.logSummary` (status and counts only).
   - Live checks read only FlowTest and assert that every event title they see starts with `[FlowTest]`.
8. **Live EventKit tests run in an app bundle** (`scripts/run_calendar_livecheck.sh`, target `FlowCalendarLiveCheck`). On macOS 26.6, `requestFullAccessToEvents` from `swift test` or other command-line processes returns `granted: false, error: nil` with no prompt, because those processes have no calendar usage description.

## Consequences
- The executor maps errors to failure categories: `noAccess`/`automationDenied` → `permissionDenied`, `calendarNotFound` → `appUnavailable`, `unrecognizedTime` → `targetNotFound`.
- Event creation or editing (later milestones) needs a new ADR and confirmation tier.
