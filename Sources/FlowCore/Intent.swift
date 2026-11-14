import Foundation

/// Router classification (spec 02 §2 `IntentRouter`).
///
/// `control` and `confirmation` are produced only by deterministic code, never by
/// the language model (spec 02 §3 global invariants; plan 03 T-010 "No LLM involved
/// in stop/cancel semantics").
public enum IntentKind: String, Sendable, Codable, CaseIterable {
    case direct
    case edit
    case task
    case dictation
    case clarification
    case confirmation
    case control
    case unsupported

    /// Kinds the model is permitted to emit.
    public static let modelEmittable: [IntentKind] = [
        .direct, .edit, .task, .dictation, .clarification, .unsupported,
    ]
}

/// Risk tier (spec 02 §6). Always derived in code from the validated action;
/// never taken from model output.
public enum RiskLevel: String, Sendable, Codable, Comparable {
    case none
    case low
    case content
    case external

    private var rank: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .content: 2
        case .external: 3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Standalone control phrases handled without the model.
public enum ControlCommand: String, Sendable, Equatable {
    case stop
    case cancel
    case stopDictation = "stop_dictation"
}

/// Where an intent came from. Model-derived intents are untrusted proposals.
public enum IntentSource: Sendable, Equatable {
    case deterministic
    case model(id: String)
}

/// A validated, typed interpretation of one user command. Nothing in this type
/// executes; it is a proposal for a later planner/executor to verify against live UI.
public struct Intent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: IntentKind
    public let action: FlowAction?
    public let control: ControlCommand?
    public let summary: String
    public let source: IntentSource

    public init(
        id: UUID = UUID(),
        kind: IntentKind,
        action: FlowAction? = nil,
        control: ControlCommand? = nil,
        summary: String,
        source: IntentSource
    ) {
        self.id = id
        self.kind = kind
        self.action = action
        self.control = control
        self.summary = summary
        self.source = source
    }

    public var risk: RiskLevel { action?.risk ?? .none }

    /// Equality ignores the random `id`.
    public static func == (lhs: Intent, rhs: Intent) -> Bool {
        lhs.kind == rhs.kind && lhs.action == rhs.action && lhs.control == rhs.control
            && lhs.summary == rhs.summary && lhs.source == rhs.source
    }
}
