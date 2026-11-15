import FlowCalendar
import Foundation

// Live EventKit check for T-024, packaged as an app bundle (scripts/run_calendar_livecheck.sh)
// because macOS only grants calendar access to bundles with a usage description; `swift test`
// processes can never be granted it. Read-only; reads ONLY the synthetic "FlowTest" calendar
// imported from fixtures/calendar/FlowTest.ics. A fixed "now" (Sat 14 Nov 2026, noon New York)
// keeps relative phrases pointing at the fixture week. Prints one line per case; exit 0 = all pass.

var newYork = Calendar(identifier: .gregorian)
newYork.timeZone = TimeZone(identifier: "America/New_York")!
let now = newYork.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!

let cases: [(String, AvailabilityStatus, String)] = [
    ("tomorrow at 4 pm", .busy, "Coffee with Sarah"),
    ("tomorrow at 10 am", .tentative, "Maybe: call with Priya"),
    ("tomorrow at 5 pm", .freeInCheckedCalendars, ""),
    ("Monday at 11 am", .busy, "Team offsite"),                    // all-day busy
    ("Tuesday at 3 pm", .busy, "Optional sync"),                   // busy + overlapping tentative
    ("Tuesday at 5 pm", .freeInCheckedCalendars, ""),
    ("Wednesday at 10 am", .freeInCheckedCalendars, ""),           // cancelled event never blocks
    ("Wednesday at 4 pm", .busy, "Weekly 1:1"),                    // recurrence, first occurrence
    ("November 25 at 4 pm", .busy, "Weekly 1:1"),                  // recurrence, later occurrence
    ("Thursday at noon", .busy, "West coast call"),                // 9 am Los Angeles = noon New York
    ("Thursday at 9 am", .freeInCheckedCalendars, ""),
    ("Friday afternoon", .busy, "Lunch with Diego"),
    ("Friday at 3 pm", .freeInCheckedCalendars, "Focus time"),     // marked free
    ("November 21 at noon", .freeInCheckedCalendars, "Birthday reminder"),  // all-day, marked free
]

@MainActor
func run() async -> Int32 {
    let store = EventKitStore()
    let access = await store.requestAccess()
    print("access: \(access.rawValue)")
    guard access == .fullAccess else { print("FAIL no full calendar access"); return 3 }
    guard store.calendars().contains(where: { $0.title == "FlowTest" }) else { print("FAIL no calendar named FlowTest"); return 4 }
    let controller = CalendarController(store: store, scope: .named(["FlowTest"]), calendar: newYork, now: { now })
    var failures = 0
    for (query, expected, mention) in cases {
        let r = await controller.check(query)
        guard let report = r.report else {
            failures += 1
            print("FAIL \(query.debugDescription) → error \(String(describing: r.error))")
            continue
        }
        let synthetic = report.findings.allSatisfy { $0.event.title.hasPrefix("[FlowTest]") }
        let ok = report.status == expected && report.calendarsChecked == ["FlowTest"] && synthetic
            && (mention.isEmpty || report.answer.contains(mention))
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL") \(query.debugDescription) → \(report.status.rawValue) (expected \(expected.rawValue)) · \(report.answer)")
    }
    // Listing a whole day, and the cancelled event being reported as not counted.
    if let tuesday = await controller.check("Tuesday").report {
        let titles = tuesday.findings.map(\.event.title)
        let ok = titles == ["[FlowTest] Design review", "[FlowTest] Optional sync"]
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL") day listing Tuesday → \(titles)")
    }
    if let wednesday = await controller.check("Wednesday at 10 am").report {
        let effects = wednesday.findings.map { "\($0.event.title)=\($0.effect.rawValue)" }
        print("INFO cancelled event as imported: \(effects)")
    }
    print("RESULT \(cases.count + 1 - failures)/\(cases.count + 1) passed")
    return failures == 0 ? 0 : 1
}

exit(await run())
