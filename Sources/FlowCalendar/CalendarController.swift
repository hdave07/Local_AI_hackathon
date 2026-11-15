import EventKit
import FlowMail
import Foundation

// MARK: - Store

/// Read-only access to calendar data. There is no create, edit or delete operation.
@MainActor
public protocol CalendarStore: AnyObject {
    func access() -> CalendarAccess
    /// Shows macOS's consent prompt when access is undetermined (never bypassed).
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date, calendarIDs: [String]) throws(CalendarError) -> [CalendarEventInfo]
}

/// EventKit-backed store. Recurring events are expanded by EventKit's predicate.
@MainActor
public final class EventKitStore: CalendarStore {
    private var store = EKEventStore()

    public init() {}

    public func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> CalendarAccess {
        guard access() == .notDetermined else { return access() }
        _ = try? await store.requestFullAccessToEvents()
        store = EKEventStore()  // a fresh store sees newly granted calendars
        return access()
    }

    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    public func events(from start: Date, to end: Date, calendarIDs: [String]) throws(CalendarError) -> [CalendarEventInfo] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { e in
            let me = e.attendees?.first(where: \.isCurrentUser)
            return CalendarEventInfo(
                id: "\(e.eventIdentifier ?? "?")@\(e.occurrenceDate?.timeIntervalSince1970 ?? 0)",
                title: e.title ?? "(untitled)", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                availability: Self.availability(e.availability), status: Self.status(e.status),
                myParticipation: me.map { Self.participation($0.participantStatus) }, calendarTitle: e.calendar?.title ?? "",
                timeZone: e.timeZone?.identifier)
        }
    }

    static func availability(_ a: EKEventAvailability) -> CalendarEventInfo.Availability {
        switch a {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        default: .notSupported
        }
    }

    static func status(_ s: EKEventStatus) -> CalendarEventInfo.Status {
        switch s {
        case .confirmed: .confirmed
        case .tentative: .tentative
        case .canceled: .canceled
        default: .none
        }
    }

    static func participation(_ p: EKParticipantStatus) -> CalendarEventInfo.Participation {
        switch p {
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .pending: .pending
        default: .other
        }
    }
}

// MARK: - Showing a day (optional, read-only navigation)

@MainActor
public protocol CalendarViewing: AnyObject {
    /// Switches Calendar to day view on `day`. Returns whether Calendar confirmed that day.
    func show(day: Date, calendar: Calendar) async throws(CalendarError) -> Bool
}

/// Calendar's scripting interface (JXA via osascript). Read-only: switches the view only.
@MainActor
public final class JXACalendarViewer: CalendarViewing {
    private let runner: ScriptRunning

    public init(runner: ScriptRunning = OSAScriptRunner()) { self.runner = runner }

    public func show(day: Date, calendar: Calendar) async throws(CalendarError) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let arg = "{\"y\":\(c.year!),\"m\":\(c.month!),\"d\":\(c.day!)}"
        let script = """
            function run(argv) {
              const a = JSON.parse(argv[0]);
              const Cal = Application('com.apple.iCal');
              Cal.activate();
              Cal.switchView({ to: 'day view' });
              Cal.viewCalendar({ at: new Date(a.y, a.m - 1, a.d, 12, 0, 0) });
              delay(0.5);
              return JSON.stringify({ ok: true });
            }
            """
        do throws(MailError) {
            let out = try await runner.run(javaScript: script, argument: arg, timeout: .seconds(20))
            return String(decoding: out, as: UTF8.self).contains("\"ok\":true")
        } catch {
            if error == .automationDenied || error == .automationNotDetermined { throw .automationDenied }
            throw .showFailed("\(error)")
        }
    }
}

// MARK: - Controller

public struct CalendarResult: Sendable, Equatable {
    public let report: CalendarReport?
    public let shownDay: Date?
    public let verified: Bool
    public let error: CalendarError?
    public let userMessage: String
}

/// T-024 controller: parse the spoken time, check access, read the scoped calendars through
/// EventKit, classify availability. Read-only.
@MainActor
public final class CalendarController {
    public let scope: CalendarScope
    let store: CalendarStore
    let viewer: CalendarViewing?
    let calendar: Calendar
    let clock: @Sendable () -> Date

    public init(store: CalendarStore, scope: CalendarScope, viewer: CalendarViewing? = nil, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.scope = scope
        self.viewer = viewer
        self.calendar = calendar
        self.clock = now
    }

    public func check(_ expression: String, now explicitNow: Date? = nil) async -> CalendarResult {
        let now = explicitNow ?? clock()
        let query: TimeQuery
        switch TimeExpressionParser.parse(expression, now: now, calendar: calendar) {
        case .success(let q): query = q
        case .failure: return failure(.unrecognizedTime(expression))
        }
        var access = store.access()
        if access == .notDetermined { access = await store.requestAccess() }
        guard access == .fullAccess else {
            // Insufficient evidence: an explicit "unknown", never "free".
            return failure(.noAccess(access))
        }
        let selected: [CalendarInfo]
        switch scope {
        case .allAuthorized:
            selected = store.calendars()
        case .named(let names):
            let wanted = Set(names.map { $0.lowercased() })
            selected = store.calendars().filter { wanted.contains($0.title.lowercased()) }
            guard !selected.isEmpty else { return failure(.calendarNotFound(names)) }
        }
        let events: [CalendarEventInfo]
        do throws(CalendarError) {
            events = try store.events(from: query.interval.start, to: query.interval.end, calendarIDs: selected.map(\.id))
        } catch {
            return failure(error)
        }
        let titles = Array(Set(selected.map(\.title))).sorted()
        let report = AvailabilityClassifier.classify(query, events: events, calendarsChecked: titles, scope: scope, access: access,
                                                     calendar: calendar)
        return CalendarResult(report: report, shownDay: nil, verified: true, error: nil, userMessage: report.answer)
    }

    public func show(_ expression: String, now explicitNow: Date? = nil) async -> CalendarResult {
        let now = explicitNow ?? clock()
        guard let viewer else { return failure(.showFailed("showing days is turned off")) }
        guard case .success(let query) = TimeExpressionParser.parse(expression, now: now, calendar: calendar) else {
            return failure(.unrecognizedTime(expression))
        }
        let day = TimeExpressionParser.describeDay(query.day, label: nil, calendar: calendar)
        do throws(CalendarError) {
            let ok = try await viewer.show(day: query.day, calendar: calendar)
            return CalendarResult(report: nil, shownDay: query.day, verified: ok, error: nil,
                                  userMessage: ok ? "Showing \(day) in Calendar." : "I asked Calendar to show \(day), but couldn't confirm it.")
        } catch {
            return failure(error)
        }
    }

    private func failure(_ error: CalendarError) -> CalendarResult {
        CalendarResult(report: nil, shownDay: nil, verified: false, error: error, userMessage: error.userMessage)
    }
}
