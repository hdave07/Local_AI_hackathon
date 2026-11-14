import Foundation

/// One finalized spoken command (plan 03 §3 shared contract
/// `Utterance(id, stableText, language, timestamp, sessionID)`).
///
/// Only *stable* (ASR-confirmed) text ever reaches this type. Interim hypotheses are
/// display-only and must never trigger actions (spec 02 §3 global invariants, §17).
public struct Utterance: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// ASR-confirmed text, whitespace-normalized. Never empty.
    public let stableText: String
    /// BCP-47-ish language code reported by the recognizer, if known (e.g. "en").
    public let language: String?
    /// When the utterance was finalized (end of speech detected).
    public let timestamp: Date
    /// Listening session this utterance belongs to (spec 02 §11 wake/continuous sessions).
    public let sessionID: UUID

    public init(
        id: UUID = UUID(),
        stableText: String,
        language: String? = nil,
        timestamp: Date = Date(),
        sessionID: UUID
    ) {
        self.id = id
        self.stableText = stableText
        self.language = language
        self.timestamp = timestamp
        self.sessionID = sessionID
    }
}
