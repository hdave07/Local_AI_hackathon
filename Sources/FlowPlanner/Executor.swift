import FlowCore
import FlowRouting
import Foundation

/// The boundary to real macOS execution (Track A: FlowWindow, FlowAX, and one adapter per
/// messaging channel — Mail, Messages, WhatsApp, … — plus Calendar).
///
/// The planner never touches macOS. It sends one allowlisted `FlowAction` at a time with
/// executor-verified bindings, and only continues on a verified result. Implementations
/// must revalidate targets against live state, honor `Task` cancellation at safe
/// checkpoints, and for `request_send` verify `bindings.approval` against the *live*
/// draft before pressing Send.
public protocol PlanExecuting: Sendable {
    func execute(_ request: ExecutionRequest) async -> ExecutionResult
}

public struct ExecutionRequest: Sendable, Equatable {
    public let planID: UUID
    public let stepID: Int
    /// 1-based attempt number for this step.
    public let attempt: Int
    public let action: FlowAction
    /// Channel adapter to use for messaging actions; nil for non-messaging actions.
    public let channel: MessageChannel?
    public let bindings: StepBindings
    public let expectation: Expectation

    public init(
        planID: UUID, stepID: Int, attempt: Int, action: FlowAction, channel: MessageChannel? = nil, bindings: StepBindings,
        expectation: Expectation
    ) {
        self.planID = planID
        self.stepID = stepID
        self.attempt = attempt
        self.action = action
        self.channel = channel
        self.bindings = bindings
        self.expectation = expectation
    }
}

/// Verified identities a step acts on. Nil means "resolve from the spoken action".
public struct StepBindings: Sendable, Equatable {
    /// For `read_message`: open exactly this message (after the user chose it).
    /// For `create_draft` replies: reply in this message's thread to its sender.
    public var message: MessageRef?
    /// For edits, review and send: the draft as last verified.
    public var draft: DraftSnapshot?
    /// For `request_send`: the user's single-use approval of exactly `draft`.
    public var approval: Approval?

    public init(message: MessageRef? = nil, draft: DraftSnapshot? = nil, approval: Approval? = nil) {
        self.message = message
        self.draft = draft
        self.approval = approval
    }
}

/// Spec 02 §5 statuses (as in Track A's `ActionStatus` / `NavigationStatus`), plus cancelled.
public enum ExecutionStatus: String, Sendable, Equatable {
    case completed
    case partiallyCompleted = "partially_completed"
    case failed
    case unsupported
    case unverified
    case needsClarification = "needs_clarification"
    case cancelled
}

/// What the executor observed after acting (re-read from live state).
public enum Observation: Sendable, Equatable {
    case none
    case appActive(KnownApp)
    case window(SelectedWindow)
    case uiActed(label: String)
    case scrolled
    /// Several messages match; the user must choose (never guessed).
    case messageCandidates([MessageRef])
    case messageOpened(MessageRef)
    /// A draft was created or changed; this is its current visible state.
    case draft(DraftSnapshot)
    /// FlowText needs an answer before editing (which occurrence; keep or discard a preview).
    /// The question moves to the shared task context; nothing was changed.
    case textChoice(prompt: String, options: [String])
    /// The draft was presented for review in this state.
    case reviewShown(DraftSnapshot)
    /// Answer of a lookup (e.g. calendar availability).
    case lookupResult(answer: String)
    /// A verified calendar availability answer with its evidence (T-024).
    case availability(AvailabilityAnswer)
    /// The channel accepted the message for sending (queued or sent). Delivery is not implied.
    case sent(draftID: String, queued: Bool)
    /// Dry-run mode: the live draft matched the approval and one send was recorded, not performed.
    case sendRehearsed(draftID: String)
}

public enum ExecutionErrorCode: String, Sendable, Equatable {
    /// The target no longer matches live state (snapshot epoch changed).
    case staleTarget = "stale_target"
    case targetNotFound = "target_not_found"
    case permissionDenied = "permission_denied"
    case appUnavailable = "app_unavailable"
    case timeout
    /// The draft changed outside Flow since it was last verified.
    case draftChanged = "draft_changed"
    /// The approval does not match the live draft.
    case approvalInvalid = "approval_invalid"
    /// The channel would address the draft to someone other than the verified recipient.
    case recipientMismatch = "recipient_mismatch"
    /// A draft for this target is already open; a second one was not created.
    case draftAlreadyOpen = "draft_already_open"
    /// The send was dispatched and Mail reported it did not send; the draft is still open, unchanged.
    case notSent = "not_sent"
    case unknown
}

public struct ExecutionResult: Sendable, Equatable {
    public let status: ExecutionStatus
    public let observation: Observation
    public let error: ExecutionErrorCode?
    /// The executor's judgment that repeating this exact request cannot duplicate an effect.
    public let retrySafe: Bool
    public let userMessage: String

    public init(
        status: ExecutionStatus, observation: Observation = .none, error: ExecutionErrorCode? = nil,
        retrySafe: Bool = false, userMessage: String = ""
    ) {
        self.status = status
        self.observation = observation
        self.error = error
        self.retrySafe = retrySafe
        self.userMessage = userMessage
    }
}
