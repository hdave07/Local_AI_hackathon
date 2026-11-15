// Copied from FlowCalendarTests (test targets cannot import each other).
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

