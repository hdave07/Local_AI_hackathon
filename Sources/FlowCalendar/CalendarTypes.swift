import Foundation

/// Calendar access as reported by EventKit.
public enum CalendarAccess: String, Sendable, Equatable {
    case fullAccess = "full_access"
    case writeOnly = "write_only"
    case denied
    case restricted
    case notDetermined = "not_determined"
}

/// Which calendars Flow reads. Development and automated tests use `.named(["FlowTest"])`;
/// the final app can use `.allAuthorized`. Answers always name what was checked.
public enum CalendarScope: Sendable, Equatable {
    case named([String])
    case allAuthorized

    public var description: String {
        switch self {
        case .named(let names): names.joined(separator: ", ") + " only"
        case .allAuthorized: "all calendars Flow can read"
        }
    }
}

public struct CalendarInfo: Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// One event occurrence as EventKit reports it (recurrences expanded).
public struct CalendarEventInfo: Sendable, Equatable {
    public enum Availability: String, Sendable { case busy, free, tentative, unavailable, notSupported = "not_supported" }
    public enum Status: String, Sendable { case none, confirmed, tentative, canceled }
    public enum Participation: String, Sendable { case accepted, declined, tentative, pending, other }

    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let availability: Availability
    public let status: Status
    /// The user's own response when the event has attendees.
    public let myParticipation: Participation?
    public let calendarTitle: String
    /// The event's own time zone, when it has one (floating events have none).
    public let timeZone: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, availability: Availability = .busy,
                status: Status = .confirmed, myParticipation: Participation? = nil, calendarTitle: String = "FlowTest",
                timeZone: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
        self.status = status
        self.myParticipation = myParticipation
        self.calendarTitle = calendarTitle
        self.timeZone = timeZone
    }
}

/// Spec 02 §10 statuses. `free` is only ever "free in the calendars checked".
public enum AvailabilityStatus: String, Sendable, Equatable {
    case busy
    case tentative
    case freeInCheckedCalendars = "free_in_checked_calendars"
    case unknown
}

/// How one overlapping event affects availability.
public enum EventEffect: String, Sendable, Equatable {
    case blocksBusy = "busy"
    case blocksTentative = "tentative"
    case ignoredCanceled = "canceled"
    case ignoredDeclined = "declined"
    case ignoredMarkedFree = "marked_free"
}

public struct EventFinding: Sendable, Equatable {
    public let event: CalendarEventInfo
    public let effect: EventEffect
}

/// A verified availability answer.
public struct CalendarReport: Sendable, Equatable {
    public let query: TimeQuery
    public let status: AvailabilityStatus
    /// Every event overlapping the query interval, with its effect.
    public let findings: [EventFinding]
    public let calendarsChecked: [String]
    /// Why the status is `unknown`, if it is.
    public let unknownReason: String?
    /// The full answer for the user (includes event titles; shown, never logged).
    public let answer: String
    /// Privacy-safe summary for logs: status and counts only.
    public var logSummary: String {
        "\(status.rawValue): \(findings.filter { $0.effect == .blocksBusy }.count) busy, "
            + "\(findings.filter { $0.effect == .blocksTentative }.count) tentative, \(findings.count) overlapping; "
            + "calendars checked: \(calendarsChecked.count)"
    }
}

public enum CalendarError: Error, Sendable, Equatable {
    case noAccess(CalendarAccess)
    case calendarNotFound([String])
    case unrecognizedTime(String)
    case eventKitFailure
    case automationDenied
    case showFailed(String)

    public var userMessage: String {
        switch self {
        case .noAccess(.denied):
            "I can't tell: Flow isn't allowed to read your calendars. Allow it in System Settings › Privacy & Security › Calendars."
        case .noAccess(.restricted): "I can't tell: calendar access is restricted on this Mac."
        case .noAccess(.writeOnly): "I can't tell: Flow can only add events, not read them. Give it full calendar access in System Settings › Privacy & Security › Calendars."
        case .noAccess: "I can't tell: Flow doesn't have calendar access yet."
        case .calendarNotFound(let names): "I can't tell: there's no calendar called \(names.joined(separator: " or ")) on this Mac."
        case .unrecognizedTime(let t): "Which day or time should I check? I couldn't place “\(t)”."
        case .eventKitFailure: "I can't tell: the calendar didn't answer."
        case .automationDenied: "Flow isn't allowed to control Calendar. Turn it on in System Settings › Privacy & Security › Automation."
        case .showFailed(let why): "I couldn't show that day in Calendar (\(why))."
        }
    }
}
