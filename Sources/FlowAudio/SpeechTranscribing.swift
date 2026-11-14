import Foundation

/// One event from a streaming recognizer, normalized away from any specific SDK.
public enum TranscriptEvent: Sendable, Equatable {
    /// Interim text that may still change. Display only; never routed (spec 02 §3).
    case hypothesis(String)
    /// Newly stable text. Engines normally report only the new segment; an engine that
    /// reports the cumulative stable transcript is also handled (see `UtteranceAssembler`).
    case confirmed(String, language: String?)
    /// Voice-activity transition, when the transcriber can report it.
    case voiceActivity(VoiceActivity)
    /// The recognizer finished a segment and has confirmed everything it will for it.
    /// Stable text can be finalized immediately.
    case endOfSegment
}

public enum VoiceActivity: Sendable, Equatable {
    case speechStarted
    case speechEnded
}

/// What a concrete recognizer actually supports, so callers never assume a feature.
public struct TranscriberCapabilities: Sendable, Equatable {
    public var interimHypotheses: Bool
    public var voiceActivityEvents: Bool
    public var customVocabulary: Bool

    public init(interimHypotheses: Bool, voiceActivityEvents: Bool, customVocabulary: Bool) {
        self.interimHypotheses = interimHypotheses
        self.voiceActivityEvents = voiceActivityEvents
        self.customVocabulary = customVocabulary
    }
}

/// A streaming speech recognizer (spec 02 §2 `AudioInput`). Implementations own
/// audio capture; they must not persist audio (PRD §9).
public protocol SpeechTranscribing: Sendable {
    var capabilities: TranscriberCapabilities { get }

    /// License activation and model download/load. Idempotent.
    func prepare() async throws(AudioError)

    /// Begin capturing and transcribing. The stream finishes when `stop()` is called or
    /// the input ends; it finishes by throwing on recognizer failure.
    func start() async throws(AudioError) -> AsyncThrowingStream<TranscriptEvent, any Error>

    /// Stop capture. Safe to call when not running.
    func stop() async
}
