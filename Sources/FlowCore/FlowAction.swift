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
    /// A voice edit of the selected draft, interpreted by FlowText against its live text
    /// ("change 3:30 to 4", "remove the last sentence", "undo that change"). Produced only
    /// by deterministic routing; never offered to the language model (ADR 0010).
    case editText = "edit_text"
    /// Window control by voice (deterministic-only; never offered to the language model).
    case minimizeWindow = "minimize_window"
    case restoreWindow = "restore_window"
    /// Closes a window (never quits the app, never answers a "save changes?" sheet).
    case closeWindow = "close_window"
    /// Lists the open windows of the apps Flow knows.
    case listWindows = "list_windows"
    /// Numbered overlay on the frontmost app's clickable controls, and choosing one by number.
    case showNumbers = "show_numbers"
    case hideNumbers = "hide_numbers"
    case chooseNumber = "choose_number"

    /// Text-editing actions, the only ones valid for `edit` / `dictation` intents.
    public var isTextAction: Bool { self == .insertText || self == .replaceText || self == .editText }

    /// Actions the language model may emit (`edit_text` and the window actions below are deterministic-only).
    public static var modelEmittable: [ActionType] { allCases.filter { !deterministicOnly.contains($0) } }

    public static let deterministicOnly: Set<ActionType> = [
        .editText, .minimizeWindow, .restoreWindow, .closeWindow, .listWindows, .showNumbers, .hideNumbers, .chooseNumber,
    ]
}

/// An app Flow can open, switch to and control windows of: any app installed on this Mac
/// (found by `AppDirectory`), identified by bundle identifier. Model output can only ever
/// name an app that is actually installed, never an arbitrary process.
///
/// Five apps have named constants (`.mail`, `.calendar`, …); Mail and Calendar also have deep
/// integrations (search, reply drafts, availability). Every other app gets app and window control.
public struct KnownApp: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The app's name as the user sees it ("Calculator", "Visual Studio Code").
    public let name: String
    public let bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public static let mail = KnownApp(name: "Mail", bundleIdentifier: "com.apple.mail")
    public static let calendar = KnownApp(name: "Calendar", bundleIdentifier: "com.apple.iCal")
    public static let notes = KnownApp(name: "Notes", bundleIdentifier: "com.apple.Notes")
    public static let finder = KnownApp(name: "Finder", bundleIdentifier: "com.apple.finder")
    public static let safari = KnownApp(name: "Safari", bundleIdentifier: "com.apple.Safari")

    /// Apps with named constants and spoken aliases (available even before apps are scanned).
    public static let allCases: [KnownApp] = [.mail, .calendar, .notes, .finder, .safari]

    /// Display name (kept for existing call sites).
    public var rawValue: String { name }
    public var description: String { name }

    // Identity is the bundle identifier (names can differ by locale or version).
    public static func == (a: KnownApp, b: KnownApp) -> Bool {
        a.bundleIdentifier.caseInsensitiveCompare(b.bundleIdentifier) == .orderedSame
    }
    public func hash(into h: inout Hasher) { h.combine(bundleIdentifier.lowercased()) }

    /// Lenient name normalization ("notes_app", "Notes.app", "the mail app", "apple calendar",
    /// "calculator", "vs code"). Returns nil unless the name is one of the named apps or an app
    /// installed on this Mac (see `AppDirectory`).
    public static func parse(_ raw: String) -> KnownApp? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "_", with: " ")
        for prefix in ["the ", "my "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        for suffix in [".app", " app", " application", " window", " windows"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s.removeLast(suffix.count)
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 60 else { return nil }
        let bare = s.hasPrefix("apple ") ? String(s.dropFirst(6)) : s
        switch bare {
        case "mail", "email", "apple mail": return .mail
        case "calendar", "ical": return .calendar
        case "notes", "note": return .notes
        case "finder": return .finder
        case "safari": return .safari
        default: break
        }
        return AppDirectory.lookup(s) ?? (bare != s ? AppDirectory.lookup(bare) : nil)
    }
}

/// The apps installed on this Mac, by spoken name. Flow.app installs a scanner at launch
/// (`InstalledAppScanner` in FlowWindow); tests install a fixed list. Without one, only the
/// named apps (`KnownApp.allCases`) are known.
public enum AppDirectory {
    public struct Entry: Sendable, Equatable {
        public let app: KnownApp
        /// Extra spoken names ("vs code" for Visual Studio Code).
        public let aliases: [String]
        public init(app: KnownApp, aliases: [String] = []) {
            self.app = app
            self.aliases = aliases
        }
    }

    final class Store: @unchecked Sendable {
        let lock = NSLock()
        var exact: [String: KnownApp] = [:]
        var entries: [Entry] = []
    }
    static let store = Store()

    /// Replaces the directory (called once at launch, and by tests).
    public static func install(_ entries: [Entry]) {
        var exact: [String: KnownApp] = [:]
        // Ambiguous keys (two apps with the same spoken name) are dropped rather than guessed.
        var ambiguous: Set<String> = []
        for e in entries {
            for key in Set(([e.app.name] + e.aliases).flatMap(keys)) {
                if let existing = exact[key], existing != e.app { ambiguous.insert(key) } else { exact[key] = e.app }
            }
        }
        for key in ambiguous { exact[key] = nil }
        store.lock.lock()
        store.exact = exact
        store.entries = entries
        store.lock.unlock()
    }

    /// Every installed app Flow knows about.
    public static var apps: [KnownApp] {
        store.lock.lock(); defer { store.lock.unlock() }
        return store.entries.map(\.app)
    }

    /// An installed app by spoken name: exact name, name without spaces, or a unique prefix
    /// of at least four letters ("calc" → Calculator). Never fuzzier than that.
    public static func lookup(_ phrase: String) -> KnownApp? {
        let key = normalize(phrase)
        guard !key.isEmpty else { return nil }
        store.lock.lock(); defer { store.lock.unlock() }
        if let app = store.exact[key] ?? store.exact[key.replacingOccurrences(of: " ", with: "")] { return app }
        guard key.count >= 4 else { return nil }
        let candidates = Set(store.entries.filter { e in
            ([e.app.name] + e.aliases).contains { normalize($0).hasPrefix(key) }
        }.map(\.app))
        return candidates.count == 1 ? candidates.first : nil
    }

    static func keys(_ name: String) -> [String] {
        let n = normalize(name)
        return [n, n.replacingOccurrences(of: " ", with: "")]
    }

    /// Lowercased letters, digits and single spaces ("Visual Studio Code" → "visual studio code").
    public static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: ".app", with: "")
        let mapped = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
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
    /// The user's edit command, verbatim (wake word and discourse openers removed).
    case editText(String)
    case minimizeWindow(WindowTarget)
    case restoreWindow(WindowTarget)
    case closeWindow(WindowTarget)
    case listWindows
    case showNumbers
    case hideNumbers
    case chooseNumber(Int)

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
        case .editText: .editText
        case .minimizeWindow: .minimizeWindow
        case .restoreWindow: .restoreWindow
        case .closeWindow: .closeWindow
        case .listWindows: .listWindows
        case .showNumbers: .showNumbers
        case .hideNumbers: .hideNumbers
        case .chooseNumber: .chooseNumber
        }
    }

    /// Spec 02 §6 risk matrix.
    public var risk: RiskLevel {
        switch self {
        case .activateApp, .moveWindow, .resizeWindow, .tileWindows, .clickElement,
            .scroll, .focus, .readMessage, .queryCalendar, .showCalendar, .requestReview,
            .minimizeWindow, .restoreWindow, .listWindows, .showNumbers, .hideNumbers, .chooseNumber:
            .low
        case .closeWindow:
            // Reversible only by reopening; the app's own "save changes?" sheet is never answered by Flow.
            .low
        case .insertText, .replaceText, .createDraft, .editText:
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
        case .editText(let command): "draft: “\(command)”"
        case .minimizeWindow(let t), .restoreWindow(let t), .closeWindow(let t): t.displayName
        case .listWindows: "open windows"
        case .showNumbers, .hideNumbers: "numbered controls"
        case .chooseNumber(let n): "number \(n)"
        }
    }
}
