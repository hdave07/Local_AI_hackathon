import CoreGraphics
import FlowCore
import FlowWindow
import Foundation

/// What the user wants to do with a target.
public enum NavigationIntent: Sendable, Equatable {
    /// Press a button-like control, or select a selectable row/cell.
    case click
    case focus
    case scroll(ScrollDirection)

    public var name: String {
        switch self {
        case .click: "click"
        case .focus: "focus"
        case .scroll(let d): "scroll \(d.rawValue)"
        }
    }
}

/// Typed navigation commands. Deterministic; no model involvement.
public enum NavCommand: Sendable, Equatable {
    case click(TargetReference, AppScope)
    case focus(TargetReference, AppScope)
    /// `nil` target means the default scroll area (D-013 predictable default for low-risk geometry).
    case scroll(TargetReference?, ScrollDirection, AppScope)
    /// Numbers actionable elements (all, or those matching the reference).
    case showNumbers(TargetReference?, AppScope)
    /// Acts on a number from the current numbered set.
    case choose(Int)
    case hideNumbers
    case inspect(AppScope)

    /// Bridge from the shared FlowCore action contract. Nil for non-navigation actions.
    /// Model output still has to pass through a planner/confirmation step before calling this.
    public init?(_ action: FlowAction) {
        switch action {
        case .clickElement(let label): self = .click(TargetReference.parse(label), .frontmost)
        case .focus(let label): self = .focus(TargetReference.parse(label), .frontmost)
        case .scroll(let direction): self = .scroll(nil, direction, .frontmost)
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .click: "click"
        case .focus: "focus"
        case .scroll(_, let d, _): "scroll \(d.rawValue)"
        case .showNumbers: "show numbers"
        case .choose(let n): "choose \(n)"
        case .hideNumbers: "hide numbers"
        case .inspect: "inspect"
        }
    }
}

/// Spec 02 §5 statuses plus a clarification request (spec 02 §3 CLARIFYING).
/// Mirrors FlowWindow's `ActionStatus` raw values; see docs/adr/0003-ui-navigation.md.
public enum NavigationStatus: String, Sendable, Equatable {
    case completed
    case partiallyCompleted = "partially_completed"
    case failed
    case unsupported
    case unverified
    case needsClarification = "needs_clarification"
}

public enum NavigationError: Error, Sendable, Equatable {
    case accessibilityNotTrusted
    case noFrontmostApp
    case appNotFound(String)
    case noWindow(String)
    /// The app exposes no usable Accessibility elements (Tier D, spec 02 §8 coverage ladder).
    case inaccessibleApp(String)
    case notFound(String)
    case targetGone
    case targetChanged(String)
    case targetDisabled(String)
    case staleNumbers
    case noActiveNumbers
    case numberOutOfRange(Int, count: Int)
    case notPressable(String)
    case notFocusable(String)
    case notScrollable(String)
    case atScrollLimit(String)
    case axFailure(operation: String, code: Int32)

    public var userMessage: String {
        switch self {
        case .accessibilityNotTrusted: "Flow needs Accessibility permission to use other apps."
        case .noFrontmostApp: "No app is in front."
        case .appNotFound(let name): "“\(name)” isn't running."
        case .noWindow(let app): "\(app) has no window to work in."
        case .inaccessibleApp(let app): "\(app) doesn't expose its controls to Accessibility, so Flow can't reach them."
        case .notFound(let ref): "I couldn't find “\(ref)” on screen."
        case .targetGone: "That control is no longer on screen, so I didn't act."
        case .targetChanged(let what): "That control changed (\(what)), so I didn't act. Try again."
        case .targetDisabled(let name): "\(name) is disabled."
        case .staleNumbers: "The screen changed since the numbers were shown. Say “show numbers” again."
        case .noActiveNumbers: "There are no numbers showing. Say “show numbers” first."
        case .numberOutOfRange(let n, let count): "There's no number \(n); choose 1 to \(count)."
        case .notPressable(let name): "\(name) can't be clicked through Accessibility."
        case .notFocusable(let name): "\(name) can't take keyboard focus."
        case .notScrollable(let name): "\(name) can't be scrolled."
        case .atScrollLimit(let edge): "Already at the \(edge)."
        case .axFailure(let op, let code): "macOS refused \(op) (AX error \(code))."
        }
    }

    /// Unsupported (honest capability limit) vs failed.
    var isCapabilityLimit: Bool {
        switch self {
        case .inaccessibleApp, .notPressable, .notFocusable, .notScrollable: true
        default: false
        }
    }

    public var retrySafe: Bool {
        switch self {
        case .axFailure, .targetGone, .targetChanged, .staleNumbers: true
        default: false
        }
    }
}

public struct NumberedTarget: Sendable, Equatable {
    public let number: Int
    public let element: UIElementInfo

    public init(number: Int, element: UIElementInfo) {
        self.number = number
        self.element = element
    }
}

/// A question for the user. Every option is a live element of snapshot `epoch`.
public struct Clarification: Sendable, Equatable {
    public let prompt: String
    public let options: [NumberedTarget]
    public let epoch: Int
    public let intent: NavigationIntent
}

public struct NavigationResult: Sendable, Equatable {
    public let actionID: UUID
    public let command: NavCommand
    public let status: NavigationStatus
    public let app: AppHandle?
    public let target: UIElementInfo?
    public let clarification: Clarification?
    public let error: NavigationError?
    /// Observations supporting the status (what changed, what was re-read).
    public let evidence: [String]
    public let userMessage: String
    public let timestamp: Date

    public var retrySafe: Bool { error?.retrySafe ?? false }
}
