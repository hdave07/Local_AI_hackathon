import FlowCore
import FlowRouting
import Foundation

/// Consequential actions that need explicit, bound approval (spec 02 §6 EXTERNAL/DESTRUCTIVE).
/// Delete has no FlowCore action yet (the MVP declines it), but approvals are typed so it
/// can be added without changing the mechanism.
public enum ConsequentialAction: String, Sendable, Equatable {
    case send
    case delete
}

/// What the user is asked to approve: exactly this action on exactly this draft state.
public struct ApprovalRequest: Sendable, Equatable {
    public let stepID: Int
    public let action: ConsequentialAction
    public let draft: DraftSnapshot
    public let prompt: String
}

/// A single-use approval bound to draft identity, version and content hash (spec 02 §3,
/// PRD §7.5). Any change to recipients, subject or body produces a different hash.
public struct Approval: Sendable, Equatable {
    public let id: UUID
    public let action: ConsequentialAction
    public let draftID: String
    public let draftVersion: Int
    public let contentHash: String
    public let issuedAt: Date
    public let expiresAt: Date

    public static let lifetime: TimeInterval = 120

    public init(id: UUID = UUID(), action: ConsequentialAction, draft: DraftSnapshot, issuedAt: Date) {
        self.id = id
        self.action = action
        self.draftID = draft.id
        self.draftVersion = draft.version
        self.contentHash = draft.contentHash
        self.issuedAt = issuedAt
        self.expiresAt = issuedAt.addingTimeInterval(Self.lifetime)
    }

    /// Still valid for this action on this exact draft state at `now`.
    public func authorizes(_ action: ConsequentialAction, on draft: DraftSnapshot, now: Date) -> Bool {
        self.action == action && draftID == draft.id && draftVersion == draft.version
            && contentHash == draft.contentHash && now < expiresAt
    }
}

/// At-most-once sending (spec 02 §3): a draft is sent once; an unverified send is never
/// retried automatically and blocks further sends until reconciled.
public struct SendLedger: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        /// Dispatched; result not yet known.
        case inFlight = "in_flight"
        case sent
        /// Timed out or could not be verified. Mail may or may not have sent it.
        case unverified
    }

    public private(set) var records: [String: Outcome] = [:]

    public init() {}

    /// Why sending `draftID` must not happen now, or nil if it may.
    public func refusal(for draftID: String) -> String? {
        switch records[draftID] {
        case nil: nil
        case .sent: "That draft was already sent."
        case .inFlight: "That draft is already being sent."
        case .unverified: "I couldn't confirm the last send. Check the conversation or Sent folder before sending again."
        }
    }

    public mutating func record(_ draftID: String, _ outcome: Outcome) {
        records[draftID] = outcome
    }

    /// The executor refused before sending (e.g. approval did not match the live draft).
    public mutating func clearInFlight(_ draftID: String) {
        if records[draftID] == .inFlight { records[draftID] = nil }
    }

    /// The user or executor confirmed the unverified send did not go out.
    public mutating func reconcileNotSent(_ draftID: String) {
        if records[draftID] == .unverified { records[draftID] = nil }
    }
}
