import FlowCore
import FlowRouting
import Foundation

/// A bounded, typed plan (spec 02 §4: ≤5 steps, allowlisted actions only).
///
/// Plans are built deterministically from validated intents. Risk, confirmation, retry
/// and failure behavior are derived in code from the action, never from model output.
public struct Plan: Sendable, Equatable, Identifiable {
    public static let maxSteps = 5

    public let id: UUID
    public let utterance: String
    public let steps: [PlanStep]

    public init(id: UUID = UUID(), utterance: String, steps: [PlanStep]) {
        self.id = id
        self.utterance = utterance
        self.steps = steps
    }

    /// Highest step risk.
    public var risk: RiskLevel { steps.map(\.risk).max() ?? .none }

    public var summary: String { steps.map(\.summary).joined(separator: " → ") }
}

public struct PlanStep: Sendable, Equatable, Identifiable {
    public let id: Int
    /// The allowlisted action (FlowCore). Recipient/target strings are what the user said;
    /// executor-verified identities travel in `ExecutionRequest.bindings`.
    public let action: FlowAction
    /// Steps that must complete (verified) before this one starts.
    public let dependsOn: [Int]
    public let preconditions: [Precondition]
    public let expectation: Expectation
    /// Spoken by the user, or added by the planner (e.g. open Mail before searching).
    public let origin: Origin
    /// Draft replies to the message selected by an earlier step.
    public let repliesToSelectedMessage: Bool
    /// Messaging channel for find/compose/review/send steps (Mail, Messages, WhatsApp, …).
    public let channel: MessageChannel?
    public let summary: String

    public enum Origin: String, Sendable, Equatable {
        case spoken
        case implied
    }

    public init(
        id: Int, action: FlowAction, dependsOn: [Int] = [], preconditions: [Precondition] = [],
        expectation: Expectation, origin: Origin = .spoken, repliesToSelectedMessage: Bool = false,
        channel: MessageChannel? = nil, summary: String
    ) {
        self.id = id
        self.action = action
        self.dependsOn = dependsOn
        self.preconditions = preconditions
        self.expectation = expectation
        self.origin = origin
        self.repliesToSelectedMessage = repliesToSelectedMessage
        self.channel = channel
        self.summary = summary
    }

    /// Spec 02 §6 risk tier, from FlowCore.
    public var risk: RiskLevel { action.risk }

    /// Generic capability of the step; the runner reasons about these, never about apps.
    public var capability: Capability { Capability(action) }

    /// Send (and, when supported, delete) needs explicit approval bound to the current draft.
    public var requiresConfirmation: Bool { risk == .external }

    /// Derived failure behavior (spec 02 §13): idempotent reads and navigation may be retried
    /// once; content changes are not retried automatically; external actions never are.
    public var failurePolicy: FailurePolicy {
        switch risk {
        case .none, .low: .retry(maxAttempts: 2)
        case .content: .stop
        case .external: .neverRetry
        }
    }
}

/// What must hold in task state before a step runs.
public enum Precondition: Sendable, Equatable {
    /// A message has been opened and verified (reply target).
    case messageSelected
    /// A Flow-authored draft exists.
    case draftExists
    /// The current draft version has been presented for review.
    case draftReviewedCurrentVersion
}

/// What the executor's observation must show for a step to count as completed.
public enum Expectation: Sendable, Equatable {
    case appFrontmost(KnownApp)
    case windowChanged
    case uiActed
    case scrolled
    /// An opened message whose sender or subject matches these spoken words.
    case messageOpened(matching: String)
    /// A draft (any channel) whose body contains `content` verbatim; recipient matches when given.
    case draftWritten(recipient: String?, content: String)
    /// The bound draft was edited by FlowText (or the edit was answered without change);
    /// the observation must be that same draft, re-read.
    case draftEdited
    /// The draft was presented for review.
    case draftShown
    /// A lookup (e.g. calendar availability) returned an answer.
    case lookupAnswered
    case sent
}

/// What a step does, independent of the app or channel that performs it.
public enum Capability: String, Sendable, Equatable {
    case activate, arrangeWindows = "arrange_windows", interact, scroll, editText = "edit_text"
    case findMessage = "find_message", compose, review, send, lookup

    public init(_ action: FlowAction) {
        switch action {
        case .activateApp: self = .activate
        case .moveWindow, .resizeWindow, .tileWindows, .minimizeWindow, .restoreWindow, .closeWindow: self = .arrangeWindows
        case .listWindows, .showNumbers: self = .lookup
        case .hideNumbers, .chooseNumber: self = .interact
        case .clickElement, .focus: self = .interact
        case .scroll: self = .scroll
        case .insertText, .replaceText, .editText: self = .editText
        case .readMessage: self = .findMessage
        case .createDraft: self = .compose
        case .requestReview: self = .review
        case .requestSend: self = .send
        case .queryCalendar: self = .lookup
        case .showCalendar: self = .interact
        }
    }

    /// Messaging capabilities carry a channel.
    public var isMessaging: Bool { [.findMessage, .compose, .review, .send].contains(self) }
}

public enum FailurePolicy: Sendable, Equatable {
    case retry(maxAttempts: Int)
    case stop
    case neverRetry
}
