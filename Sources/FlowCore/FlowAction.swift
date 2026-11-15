import Foundation

/// The finite action allowlist (spec 02 §4). Raw values are the wire names the
/// model must use. Anything else is rejected as an unsupported action.
public enum ActionType: String, Sendable, Codable, CaseIterable {
    case activateApp = "activate_app"
    case moveWindow = "move_window"
    case resizeWindow = "resize_window"
    case tileWindows = "tile_windows"
    case clickElement = "click_element"
    case scroll
    case focus
    case insertText = "insert_text"
    case replaceText = "replace_text"
    case createDraft = "create_draft"
    case readMessage = "read_message"
    case queryCalendar = "query_calendar"
    /// Show a day in the Calendar app (read-only navigation).
    case showCalendar = "show_calendar"
    case requestReview = "request_review"
    case requestSend = "request_send"

    /// Text-editing actions, the only ones valid for `edit` / `dictation` intents.
    public var isTextAction: Bool { self == .insertText || self == .replaceText }
}

/// Apps Flow targets in the MVP (PRD D-004: Mail and Calendar anchor; Finder,
/// Notes and Safari have limited generic coverage). Other apps are rejected so
/// model output can never name an arbitrary process.
public enum KnownApp: String, Sendable, Codable, CaseIterable {
    case mail = "Mail"
    case calendar = "Calendar"
    case notes = "Notes"
    case finder = "Finder"
    case safari = "Safari"

    public var bundleIdentifier: String {
        switch self {
        case .mail: "com.apple.mail"
        case .calendar: "com.apple.iCal"
        case .notes: "com.apple.Notes"
        case .finder: "com.apple.finder"
        case .safari: "com.apple.Safari"
        }
    }

    /// Lenient name normalization for a small model ("notes_app", "Notes.app",
    /// "the mail app", "apple calendar"). Returns nil for anything not allowlisted.
    public static func parse(_ raw: String) -> KnownApp? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "_", with: " ")
        for prefix in ["the ", "apple ", "macos "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        for suffix in [".app", " app", " application"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        s = s.trimmingCharacters(in: .whitespaces)
        switch s {
        case "mail", "email", "apple mail": return .mail
        case "calendar", "ical": return .calendar
        case "notes", "note": return .notes
        case "finder": return .finder
        case "safari": return .safari
        default: return nil
        }
    }
}

public enum WindowTarget: Sendable, Equatable {
    case active
    case app(KnownApp)

    public var displayName: String {
        switch self {
        case .active: "active window"
        case .app(let app): app.rawValue
        }
    }
}

/// Standard window placements (spec 02 §7). Coordinates are computed by code later,
/// never by the model.
public enum WindowPosition: String, Sendable, CaseIterable {
    case leftHalf = "left_half"
    case rightHalf = "right_half"
    case maximize
    case center

    public static func parse(_ raw: String) -> WindowPosition? {
        switch normalizeToken(raw) {
        case "left_half", "left": .leftHalf
        case "right_half", "right": .rightHalf
        case "maximize", "maximized", "full", "full_screen", "fullscreen": .maximize
        case "center", "centre", "middle": .center
        default: nil
        }
    }
}

/// Relative resize using preconfigured deltas (spec 02 §7), not model coordinates.
public enum ResizeChange: String, Sendable, CaseIterable {
    case wider, narrower, taller, shorter, larger, smaller

    public static func parse(_ raw: String) -> ResizeChange? {
        switch normalizeToken(raw) {
        case "wider": .wider
        case "narrower", "thinner": .narrower
        case "taller": .taller
        case "shorter": .shorter
        case "larger", "bigger": .larger
        case "smaller": .smaller
        default: nil
        }
    }
}

public enum ScrollDirection: String, Sendable, CaseIterable {
    case up, down, top, bottom

    public static func parse(_ raw: String) -> ScrollDirection? {
        ScrollDirection(rawValue: normalizeToken(raw))
    }
}

func normalizeToken(_ raw: String) -> String {
    raw.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "-", with: "_")
}

/// Strict discriminated action type: each case carries only its validated arguments.
public enum FlowAction: Sendable, Equatable {
    case activateApp(KnownApp)
    case moveWindow(WindowTarget, WindowPosition)
    case resizeWindow(WindowTarget, ResizeChange)
    case tileWindows(left: KnownApp, right: KnownApp)
    case clickElement(label: String)
    case scroll(ScrollDirection)
    case focus(label: String)
    case insertText(String)
    case replaceText(old: String, new: String)
    case createDraft(recipient: String, content: String)
    case readMessage(query: String)
    case queryCalendar(timeExpression: String)
    case showCalendar(dateExpression: String)
    case requestReview
    case requestSend

    public var type: ActionType {
        switch self {
        case .activateApp: .activateApp
        case .moveWindow: .moveWindow
        case .resizeWindow: .resizeWindow
        case .tileWindows: .tileWindows
        case .clickElement: .clickElement
        case .scroll: .scroll
        case .focus: .focus
        case .insertText: .insertText
        case .replaceText: .replaceText
        case .createDraft: .createDraft
        case .readMessage: .readMessage
        case .queryCalendar: .queryCalendar
        case .showCalendar: .showCalendar
        case .requestReview: .requestReview
        case .requestSend: .requestSend
        }
    }

    /// Spec 02 §6 risk matrix.
    public var risk: RiskLevel {
        switch self {
        case .activateApp, .moveWindow, .resizeWindow, .tileWindows, .clickElement,
            .scroll, .focus, .readMessage, .queryCalendar, .showCalendar, .requestReview:
            .low
        case .insertText, .replaceText, .createDraft:
            .content
        case .requestSend:
            .external
        }
    }

    /// Human-readable target for display.
    public var targetDescription: String {
        switch self {
        case .activateApp(let app): app.rawValue
        case .moveWindow(let t, let p): "\(t.displayName) → \(p.rawValue)"
        case .resizeWindow(let t, let c): "\(t.displayName) → \(c.rawValue)"
        case .tileWindows(let l, let r): "\(l.rawValue) (left), \(r.rawValue) (right)"
        case .clickElement(let label), .focus(let label): "“\(label)”"
        case .scroll(let d): d.rawValue
        case .insertText(let text): "“\(text)”"
        case .replaceText(let old, let new): "“\(old)” → “\(new)”"
        case .createDraft(let recipient, let content):
            content.isEmpty ? "to \(recipient)" : "to \(recipient): “\(content)”"
        case .readMessage(let q): "“\(q)”"
        case .queryCalendar(let t): t
        case .showCalendar(let d): d
        case .requestReview, .requestSend: "current draft"
        }
    }
}
