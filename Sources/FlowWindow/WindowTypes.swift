import CoreGraphics
import FlowCore
import Foundation

/// Session-scoped identifier the backend assigns to a live window. Never reused,
/// and every action re-validates it against the app's current window list.
public struct WindowID: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public var description: String { "w\(raw)" }
}

/// A running application as seen by the backend.
public struct AppHandle: Sendable, Equatable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    public init(pid: pid_t, bundleID: String, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// Freshly read window state. Frames use Accessibility coordinates: global points,
/// origin at the top-left of the primary display, y increasing downward.
public struct WindowState: Sendable, Equatable {
    public let id: WindowID
    public let app: AppHandle
    public let title: String
    public let frame: CGRect
    public let isStandard: Bool
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let canMove: Bool
    public let canResize: Bool
    public let canMinimize: Bool

    public init(
        id: WindowID, app: AppHandle, title: String, frame: CGRect, isStandard: Bool = true,
        isMinimized: Bool = false, isFullScreen: Bool = false, canMove: Bool = true,
        canResize: Bool = true, canMinimize: Bool = true
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.isStandard = isStandard
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.canMove = canMove
        self.canResize = canResize
        self.canMinimize = canMinimize
    }

    public var displayName: String { title.isEmpty ? "\(app.name) window" : "\(app.name) — \(title)" }
}

/// Which window a command targets. `title` narrows among same-app windows.
public struct WindowSelector: Sendable, Equatable {
    public let target: WindowTarget
    public let title: String?

    public init(_ target: WindowTarget, title: String? = nil) {
        self.target = target
        self.title = title
    }

    public static func app(_ app: KnownApp, title: String? = nil) -> WindowSelector {
        WindowSelector(.app(app), title: title)
    }

    public static let active = WindowSelector(.active)
}

/// Typed window/app commands. Deterministic: no model involvement.
public enum WindowCommand: Sendable, Equatable {
    case activate(KnownApp)
    case move(WindowSelector, WindowPosition)
    case resize(WindowSelector, ResizeChange)
    case tile(left: KnownApp, right: KnownApp)
    case minimize(WindowSelector)
    case restore(WindowSelector)
    case undo

    /// Bridge from the shared FlowCore action contract (read-only use of FlowCore).
    /// Returns nil for actions that are not window/app control.
    public init?(_ action: FlowAction) {
        switch action {
        case .activateApp(let app): self = .activate(app)
        case .moveWindow(let target, let position): self = .move(WindowSelector(target), position)
        case .resizeWindow(let target, let change): self = .resize(WindowSelector(target), change)
        case .tileWindows(let left, let right): self = .tile(left: left, right: right)
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .activate: "activate"
        case .move: "move"
        case .resize: "resize"
        case .tile: "tile"
        case .minimize: "minimize"
        case .restore: "restore"
        case .undo: "undo"
        }
    }
}

/// Spec 02 §5 status values, plus `unsupported` (requested for Track A; see
/// docs/adr/0001-window-action-results.md).
public enum ActionStatus: String, Sendable, Equatable {
    case completed
    case partiallyCompleted = "partially_completed"
    case failed
    case unsupported
    case unverified
}

public enum UnsupportedReason: String, Sendable, Equatable {
    case fullScreen = "window is full screen"
    case notMovable = "window cannot be moved"
    case notResizable = "window cannot be resized"
    case notMinimizable = "window cannot be minimized"
    case atSizeLimit = "window is already at its size limit"
    case sameApp = "both sides are the same app"
}

public enum WindowError: Error, Sendable, Equatable {
    case accessibilityNotTrusted
    case appNotInstalled(String)
    case appNotRunning(String)
    case launchFailed(String)
    case noFrontmostApp
    case noWindow(String)
    case ambiguousWindow(app: String, candidates: [String])
    case windowGone
    case noScreen
    case axFailure(operation: String, code: Int32)
    case nothingToUndo
    case changedSinceAction(String)

    public var userMessage: String {
        switch self {
        case .accessibilityNotTrusted: "Flow needs Accessibility permission to control windows."
        case .appNotInstalled(let app): "\(app) isn't installed."
        case .appNotRunning(let app): "\(app) isn't open."
        case .launchFailed(let app): "\(app) couldn't be opened."
        case .noFrontmostApp: "No app is in front."
        case .noWindow(let app): "\(app) has no matching window."
        case .ambiguousWindow(let app, let candidates):
            "\(app) has \(candidates.count) windows. Which one? " + candidates.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }.joined(separator: ", ")
        case .windowGone: "That window has closed."
        case .noScreen: "No display is available."
        case .axFailure(let op, let code): "macOS refused \(op) (AX error \(code))."
        case .nothingToUndo: "There's nothing to undo."
        case .changedSinceAction(let what): "Can't undo: \(what) changed since Flow moved it."
        }
    }

    public var retrySafe: Bool {
        switch self {
        case .axFailure, .windowGone, .noWindow, .noFrontmostApp: true
        default: false
        }
    }
}

public struct WindowRef: Sendable, Equatable {
    public let id: WindowID
    public let appBundleID: String
    public let appName: String
    public let title: String

    public init(_ state: WindowState) {
        id = state.id
        appBundleID = state.app.bundleID
        appName = state.app.name
        title = state.title
    }
}

/// Typed outcome of one command (spec 02 §5 shape). Only `.completed` may be
/// presented as success.
public struct WindowActionResult: Sendable, Equatable {
    public let actionID: UUID
    public let command: WindowCommand
    public let status: ActionStatus
    public let targets: [WindowRef]
    public let before: [CGRect]
    public let observed: [WindowState]
    public let expected: [CGRect]
    /// Independent check against the window server (CGWindowList bounds), when available.
    public let windowServerConfirmed: Bool?
    public let error: WindowError?
    public let unsupportedReason: UnsupportedReason?
    public let undoToken: UUID?
    public let userMessage: String
    public let timestamp: Date

    public var retrySafe: Bool { error?.retrySafe ?? false }
}
