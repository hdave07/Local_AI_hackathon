@testable import FlowCalendar
import Foundation
import Testing

let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

/// Saturday 14 Nov 2026, 12:00 in New York.
let saturdayNoon = newYork.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!

func ny(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func parse(_ s: String, now: Date = saturdayNoon) -> TimeQuery? {
    try? TimeExpressionParser.parse(s, now: now, calendar: newYork).get()
}

@Suite("Time expressions")
struct TimeExpressionTests {
    @Test(arguments: [
        ("at four", 11, 14, 16, 0, TimeQuery.Kind.moment),
        ("at 4 tomorrow", 11, 15, 16, 0, .moment),
        ("tomorrow at 4", 11, 15, 16, 0, .moment),
        ("at four pm tomorrow", 11, 15, 16, 0, .moment),
        ("at 10 am on Tuesday", 11, 17, 10, 0, .moment),
        ("Thursday at noon", 11, 19, 12, 0, .moment),
        ("November 20 at 1 pm", 11, 20, 13, 0, .moment),
        ("4:30 pm", 11, 14, 16, 30, .moment),
        ("at 9", 11, 14, 9, 0, .moment),
        ("Friday afternoon", 11, 20, 12, 0, .range),
        ("this afternoon", 11, 14, 12, 0, .range),
        ("tonight", 11, 14, 18, 0, .range),
        ("tomorrow", 11, 15, 0, 0, .day),
        ("Monday", 11, 16, 0, 0, .day),
        ("next Saturday", 11, 21, 0, 0, .day),
        ("between 2 and 4 tomorrow", 11, 15, 14, 0, .range),
    ])
    func resolves(text: String, month: Int, day: Int, hour: Int, minute: Int, kind: TimeQuery.Kind) throws {
        let q = try #require(parse(text))
        #expect(q.interval.start == ny(month, day, hour, minute), "\(text): \(q.description)")
        #expect(q.kind == kind)
    }

    @Test func momentIsAHalfHourSlot() throws {
        let q = try #require(parse("at 4 tomorrow"))
        #expect(q.interval.duration == 30 * 60)
        #expect(q.description == "tomorrow (Sun 15 Nov) at 4:00 PM")
    }

    @Test func ambiguousHourIsStatedNotHidden() throws {
        let q = try #require(parse("at four"))
        #expect(q.assumptions.contains("I took that as 4:00 PM"))
        #expect(q.assumptions.contains("I assumed you meant today"))
        #expect(try #require(parse("at 4 pm today")).assumptions.isEmpty)
        #expect(try #require(parse("this afternoon")).assumptions.isEmpty)
    }

    @Test func rangesAndDays() throws {
        let afternoon = try #require(parse("Friday afternoon"))
        #expect(afternoon.interval.end == ny(11, 20, 17))
        let day = try #require(parse("tomorrow"))
        #expect(day.interval.end == ny(11, 16, 0))
        let between = try #require(parse("between 2 and 4 tomorrow"))
        #expect(between.interval.end == ny(11, 15, 16))
        let weekend = try #require(parse("this weekend"))
        #expect(weekend.interval.start == ny(11, 14, 0))
        #expect(weekend.interval.end == ny(11, 16, 0))
    }

    @Test func monthBeforeTodayMeansNextYear() throws {
        #expect(try #require(parse("January 3")).interval.start == ny(1, 3, 0, year: 2027))
    }

    @Test func daylightSavingDayIsHandledByTheCalendar() throws {
        // Sun 8 Mar 2026: clocks go forward at 2 am in New York (a 23-hour day).
        let saturday = ny(3, 7, 12)
        let q = try #require(parse("tomorrow at 4", now: saturday))
        #expect(q.interval.start == ny(3, 8, 16))
        #expect(newYork.timeZone.secondsFromGMT(for: q.interval.start) == -4 * 3600, "EDT after the change")
        let day = try #require(parse("tomorrow", now: saturday))
        #expect(day.interval.duration == 23 * 3600)
    }

    @Test(arguments: ["blah", "the purple one", ""])
    func unrecognized(text: String) {
        #expect(parse(text) == nil)
    }
}

@Suite("Availability classification")
struct AvailabilityTests {
    let fourPM = try! TimeExpressionParser.parse("tomorrow at 4 pm", now: saturdayNoon, calendar: newYork).get()

    func classify(_ events: [CalendarEventInfo], access: CalendarAccess = .fullAccess, calendars: [String] = ["FlowTest"],
                  scope: CalendarScope = .named(["FlowTest"]), query: TimeQuery? = nil) -> CalendarReport {
        AvailabilityClassifier.classify(query ?? fourPM, events: events, calendarsChecked: calendars, scope: scope, access: access,
                                        calendar: newYork)
    }

    func event(_ title: String, _ h1: Int, _ h2: Int, day: Int = 15, allDay: Bool = false, availability: CalendarEventInfo.Availability = .busy,
               status: CalendarEventInfo.Status = .confirmed, me: CalendarEventInfo.Participation? = nil) -> CalendarEventInfo {
        CalendarEventInfo(id: title, title: title, start: allDay ? ny(11, day, 0) : ny(11, day, h1),
                          end: allDay ? ny(11, day + 1, 0) : ny(11, day, h2), isAllDay: allDay, availability: availability,
                          status: status, myParticipation: me)
    }

    @Test func busyEvent() {
        let r = classify([event("Coffee", 16, 17)])
        #expect(r.status == .busy)
        #expect(r.answer == "In your FlowTest calendar, you're busy tomorrow (Sun 15 Nov) at 4:00 PM: Coffee (4:00 PM–5:00 PM).")
    }

    @Test func busyOutranksTentativeAndBothAreListed() {
        let r = classify([event("Optional", 16, 17, status: .tentative), event("Review", 15, 17)])
        #expect(r.status == .busy)
        #expect(r.findings.map(\.effect) == [.blocksBusy, .blocksTentative])
    }

    @Test func tentativeOnly() {
        #expect(classify([event("Maybe", 16, 17, status: .tentative)]).status == .tentative)
        #expect(classify([event("Invite", 16, 17, me: .pending)]).status == .tentative)
    }

    @Test func cancelledDeclinedAndFreeMarkedDoNotBlock() {
        let r = classify([event("Cancelled", 16, 17, status: .canceled), event("Declined", 16, 17, me: .declined),
                          event("Focus", 16, 17, availability: .free)])
        #expect(r.status == .freeInCheckedCalendars)
        #expect(r.answer.contains("Not counted:"))
        #expect(r.answer.hasPrefix("Nothing is scheduled tomorrow (Sun 15 Nov) at 4:00 PM in your FlowTest calendar, so you look free."))
    }

    @Test func allDayBusyBlocksAllDayFreeDoesNot() {
        #expect(classify([event("Offsite", 0, 0, allDay: true)]).status == .busy)
        #expect(classify([event("Birthday", 0, 0, allDay: true, availability: .free)]).status == .freeInCheckedCalendars)
    }

    @Test func boundariesDoNotOverlap() {
        #expect(classify([event("Before", 15, 16), event("After", 16, 17, day: 16)]).status == .freeInCheckedCalendars)
    }

    @Test func outOfOfficeIsBusy() {
        #expect(classify([event("OOO", 9, 18, availability: .unavailable)]).status == .busy)
    }

    @Test(arguments: [CalendarAccess.denied, .writeOnly, .restricted, .notDetermined])
    func incompleteAccessIsNeverFree(access: CalendarAccess) {
        let r = classify([], access: access)
        #expect(r.status == .unknown)
        #expect(!r.answer.contains("free."))
    }

    @Test func noCalendarsIsUnknown() {
        #expect(classify([], calendars: []).status == .unknown)
    }

    @Test func allCalendarsScopeNamesThem() {
        let r = classify([], calendars: ["Home", "Work"], scope: .allAuthorized)
        #expect(r.answer == "Nothing is scheduled tomorrow (Sun 15 Nov) at 4:00 PM in your calendars (Home, Work), so you look free.")
    }

    @Test func logSummaryHasNoTitles() {
        let r = classify([event("Private dinner", 16, 17)])
        #expect(!r.logSummary.contains("Private"))
        #expect(r.logSummary.hasPrefix("busy: 1 busy"))
    }
}

@MainActor
final class FakeCalendarStore: CalendarStore {
    var accessValue: CalendarAccess = .fullAccess
    var grantOnRequest = true
    var calendarList = [CalendarInfo(id: "c-test", title: "FlowTest"), CalendarInfo(id: "c-home", title: "Home")]
    var eventsByCalendar: [String: [CalendarEventInfo]] = [:]
    private(set) var requested = 0
    private(set) var queriedIDs: [[String]] = []

    func access() -> CalendarAccess { accessValue }
    func requestAccess() async -> CalendarAccess {
        requested += 1
        if accessValue == .notDetermined { accessValue = grantOnRequest ? .fullAccess : .denied }
        return accessValue
    }
    func calendars() -> [CalendarInfo] { calendarList }
    func events(from start: Date, to end: Date, calendarIDs: [String]) throws(CalendarError) -> [CalendarEventInfo] {
        queriedIDs.append(calendarIDs)
        return calendarIDs.flatMap { eventsByCalendar[$0] ?? [] }.filter { $0.start < end && $0.end > start }
    }
}

@MainActor
final class FakeViewer: CalendarViewing {
    var shown: [Date] = []
    var error: CalendarError?
    func show(day: Date, calendar: Calendar) async throws(CalendarError) -> Bool {
        if let error { throw error }
        shown.append(day)
        return true
    }
}

@MainActor
@Suite("CalendarController")
struct CalendarControllerTests {
    func controller(_ store: FakeCalendarStore, scope: CalendarScope = .named(["FlowTest"]), viewer: CalendarViewing? = nil) -> CalendarController {
        CalendarController(store: store, scope: scope, viewer: viewer, calendar: newYork)
    }

    @Test func readsOnlyTheScopedCalendar() async throws {
        let store = FakeCalendarStore()
        store.eventsByCalendar["c-home"] = [CalendarEventInfo(id: "p", title: "Private", start: ny(11, 15, 16), end: ny(11, 15, 17), calendarTitle: "Home")]
        let r = await controller(store).check("tomorrow at 4", now: saturdayNoon)
        #expect(r.report?.status == .freeInCheckedCalendars)
        #expect(store.queriedIDs == [["c-test"]], "the Home calendar is never read in test mode")
        #expect(r.report?.calendarsChecked == ["FlowTest"])
    }

    @Test func allAuthorizedReadsEverything() async {
        let store = FakeCalendarStore()
        store.eventsByCalendar["c-home"] = [CalendarEventInfo(id: "p", title: "Dinner", start: ny(11, 15, 16), end: ny(11, 15, 17), calendarTitle: "Home")]
        let r = await controller(store, scope: .allAuthorized).check("tomorrow at 4", now: saturdayNoon)
        #expect(r.report?.status == .busy)
        #expect(r.report?.calendarsChecked == ["FlowTest", "Home"])
    }

    @Test func undeterminedAccessIsRequestedOnce() async {
        let store = FakeCalendarStore()
        store.accessValue = .notDetermined
        let r = await controller(store).check("tomorrow at 4", now: saturdayNoon)
        #expect(store.requested == 1)
        #expect(r.report != nil)
    }

    @Test(arguments: [CalendarAccess.denied, .writeOnly, .restricted])
    func noAccessIsAClearUnknown(access: CalendarAccess) async {
        let store = FakeCalendarStore()
        store.accessValue = access
        let r = await controller(store).check("tomorrow at 4", now: saturdayNoon)
        #expect(r.error == .noAccess(access))
        #expect(r.userMessage.hasPrefix("I can't tell"))
        #expect(store.queriedIDs.isEmpty)
    }

    @Test func missingTestCalendar() async {
        let store = FakeCalendarStore()
        store.calendarList = [CalendarInfo(id: "c-home", title: "Home")]
        let r = await controller(store).check("tomorrow at 4", now: saturdayNoon)
        #expect(r.error == .calendarNotFound(["FlowTest"]))
        #expect(store.queriedIDs.isEmpty)
    }

    @Test func unrecognizedTime() async {
        #expect(await controller(FakeCalendarStore()).check("the purple one", now: saturdayNoon).error == .unrecognizedTime("the purple one"))
    }

    @Test func showDayIsOptionalAndReadOnly() async {
        #expect(await controller(FakeCalendarStore()).show("tomorrow", now: saturdayNoon).error != nil, "no viewer: not shown")
        let viewer = FakeViewer()
        let r = await controller(FakeCalendarStore(), viewer: viewer).show("Friday", now: saturdayNoon)
        #expect(r.verified)
        #expect(viewer.shown == [ny(11, 20, 0)])
        viewer.error = .automationDenied
        #expect(await controller(FakeCalendarStore(), viewer: viewer).show("Friday", now: saturdayNoon).error == .automationDenied)
    }
}
