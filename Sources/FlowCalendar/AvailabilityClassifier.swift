import Foundation

/// Pure availability classification (spec 02 §10). Never says "free" without full access to
/// at least one checked calendar; cancelled, declined and free-marked events never block;
/// busy outranks tentative.
public enum AvailabilityClassifier {
    public static func effect(of e: CalendarEventInfo) -> EventEffect {
        if e.status == .canceled { return .ignoredCanceled }
        if e.myParticipation == .declined { return .ignoredDeclined }
        if e.availability == .free { return .ignoredMarkedFree }
        if e.status == .tentative || e.availability == .tentative || e.myParticipation == .tentative || e.myParticipation == .pending {
            return .blocksTentative
        }
        return .blocksBusy  // busy, unavailable (out of office), or not supported by the calendar
    }

    public static func classify(_ query: TimeQuery, events: [CalendarEventInfo], calendarsChecked: [String],
                                scope: CalendarScope, access: CalendarAccess, calendar: Calendar = .current) -> CalendarReport {
        let overlapping = events
            .filter { $0.start < query.interval.end && $0.end > query.interval.start }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let findings = overlapping.map { EventFinding(event: $0, effect: effect(of: $0)) }
        let whereChecked = Self.whereChecked(calendarsChecked, scope)

        var unknown: String?
        if access != .fullAccess { unknown = "Flow doesn't have full access to your calendars" }
        else if calendarsChecked.isEmpty { unknown = "there are no calendars to check" }

        let status: AvailabilityStatus
        if unknown != nil { status = .unknown }
        else if findings.contains(where: { $0.effect == .blocksBusy }) { status = .busy }
        else if findings.contains(where: { $0.effect == .blocksTentative }) { status = .tentative }
        else { status = .freeInCheckedCalendars }

        let answer = Self.answer(query, status: status, findings: findings, whereChecked: whereChecked, unknown: unknown,
                                 calendar: calendar)
        return CalendarReport(query: query, status: status, findings: findings, calendarsChecked: calendarsChecked,
                              unknownReason: unknown, answer: answer)
    }

    static func whereChecked(_ names: [String], _ scope: CalendarScope) -> String {
        switch scope {
        case .named:
            let list = names.isEmpty ? "the requested" : names.joined(separator: " and ")
            return "your \(list) calendar\(names.count == 1 ? "" : "s")"
        case .allAuthorized:
            return names.isEmpty ? "your calendars" : "your calendars (\(names.joined(separator: ", ")))"
        }
    }

    static func answer(_ q: TimeQuery, status: AvailabilityStatus, findings: [EventFinding], whereChecked: String, unknown: String?,
                       calendar: Calendar) -> String {
        func span(_ e: CalendarEventInfo) -> String {
            e.isAllDay ? "all day" : "\(clock(e.start, calendar))–\(clock(e.end, calendar))"
        }
        func item(_ f: EventFinding) -> String {
            switch f.effect {
            case .blocksBusy: "\(f.event.title) (\(span(f.event)))"
            case .blocksTentative: "\(f.event.title) (\(span(f.event)), tentative)"
            case .ignoredCanceled: "\(f.event.title) (cancelled)"
            case .ignoredDeclined: "\(f.event.title) (you declined)"
            case .ignoredMarkedFree: "\(f.event.title) (\(span(f.event)), marked free)"
            }
        }
        let note = q.assumptions.isEmpty ? "" : " (" + q.assumptions.joined(separator: "; ") + ".)"
        let blocking = findings.filter { $0.effect == .blocksBusy || $0.effect == .blocksTentative }
        let ignored = findings.filter { !($0.effect == .blocksBusy || $0.effect == .blocksTentative) }
        let ignoredText = ignored.isEmpty ? "" : " Not counted: " + ignored.map(item).joined(separator: "; ") + "."

        switch status {
        case .unknown:
            return "I can't tell whether you're free \(q.description): \(unknown ?? "not enough information").\(note)"
        case .busy:
            return "In \(whereChecked), you're busy \(q.description): " + blocking.map(item).joined(separator: "; ") + "." + ignoredText + note
        case .tentative:
            return "In \(whereChecked), you have something tentative \(q.description): " + blocking.map(item).joined(separator: "; ") + "."
                + ignoredText + note
        case .freeInCheckedCalendars:
            // "in your FlowTest calendar" names exactly what was checked; nothing broader is claimed.
            return "Nothing is scheduled \(q.description) in \(whereChecked), so you look free." + ignoredText + note
        }
    }

    static func clock(_ d: Date, _ calendar: Calendar) -> String { TimeExpressionParser.clockText(d, calendar) }
}
