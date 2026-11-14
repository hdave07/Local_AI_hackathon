import Foundation

/// When a stream of stable segments becomes one finalized utterance.
public struct EndpointPolicy: Sendable, Equatable {
    /// Quiet time after the last activity before stable text is finalized.
    public var trailingSilence: TimeInterval
    /// If only unconfirmed hypothesis text remains for this long without change, the
    /// utterance is reported `incomplete` and is *not* routed (no action on partials).
    public var unconfirmedTailTimeout: TimeInterval
    /// Hard cap on one utterance, so continuous noise cannot hold the pipeline forever.
    public var maxUtteranceDuration: TimeInterval

    public init(
        trailingSilence: TimeInterval = 0.7,
        unconfirmedTailTimeout: TimeInterval = 4.0,
        maxUtteranceDuration: TimeInterval = 30
    ) {
        self.trailingSilence = trailingSilence
        self.unconfirmedTailTimeout = unconfirmedTailTimeout
        self.maxUtteranceDuration = maxUtteranceDuration
    }
}

/// What the HUD may show while the user is speaking.
public struct PartialTranscript: Sendable, Equatable {
    public let confirmed: String
    public let hypothesis: String

    public init(confirmed: String, hypothesis: String) {
        self.confirmed = confirmed
        self.hypothesis = hypothesis
    }

    public var displayText: String {
        [confirmed, hypothesis].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public enum AssemblerOutput: Sendable, Equatable {
    /// Display-only progress.
    case partial(PartialTranscript)
    /// Stable, finalized text: the only output that may be routed.
    case final(text: String, language: String?)
    /// Speech ended with text the recognizer never confirmed. Shown, never routed.
    case incomplete(PartialTranscript)
}

/// Pure state machine turning `TranscriptEvent`s into finalized utterances.
///
/// Times are seconds on any monotonic clock, supplied by the caller, which keeps
/// every transition deterministic and unit-testable.
///
/// Rules:
/// - Hypotheses only update display; they never finalize.
/// - Stable text finalizes after `trailingSilence` with no pending hypothesis and no
///   active speech (when VAD is available).
/// - A pending hypothesis blocks finalization; after `unconfirmedTailTimeout` it is
///   reported `incomplete` and dropped.
public struct UtteranceAssembler: Sendable {
    public enum Phase: Sendable, Equatable {
        case idle
        case hearing
    }

    public let policy: EndpointPolicy
    public private(set) var phase: Phase = .idle
    public private(set) var confirmed = ""
    public private(set) var hypothesis = ""
    public private(set) var speechActive = false
    private var language: String?
    private var lastActivity: TimeInterval?
    private var startedAt: TimeInterval?
    /// Everything already finalized in this stream, used to strip the prefix when an
    /// engine reports a cumulative transcript.
    private var finalizedHistory = ""

    public init(policy: EndpointPolicy = EndpointPolicy()) {
        self.policy = policy
    }

    public var partial: PartialTranscript { PartialTranscript(confirmed: confirmed, hypothesis: hypothesis) }

    public mutating func ingest(_ event: TranscriptEvent, at now: TimeInterval) -> [AssemblerOutput] {
        switch event {
        case .hypothesis(let raw):
            let text = Self.normalize(raw)
            // An unchanged hypothesis is not new activity (it must not postpone the timeout).
            guard text != hypothesis else { return [] }
            hypothesis = text
            if phase == .idle && text.isEmpty { return [] }
            begin(now)
            touch(now)
            return [.partial(partial)]

        case .confirmed(let raw, let lang):
            var text = Self.normalize(raw)
            if !finalizedHistory.isEmpty, Self.hasPrefix(text, finalizedHistory) {
                text = Self.normalize(String(text.dropFirst(finalizedHistory.count)))
            }
            guard !text.isEmpty else { return [] }
            if confirmed.isEmpty {
                confirmed = text
            } else if Self.hasPrefix(text, confirmed) {
                confirmed = text  // cumulative engine
            } else {
                confirmed += " " + text
            }
            // The engine re-sends any remaining hypothesis after a confirmation.
            hypothesis = ""
            if let lang { language = lang }
            begin(now)
            touch(now)
            return [.partial(partial)]

        case .voiceActivity(.speechStarted):
            speechActive = true
            if phase == .hearing { touch(now) }
            return []

        case .voiceActivity(.speechEnded):
            speechActive = false
            if phase == .hearing { touch(now) }
            return []

        case .endOfSegment:
            // Nothing more will be confirmed for this speech: finalize stable text now,
            // or report leftover hypothesis as incomplete. Never routes a hypothesis.
            // (VAD state is left alone: the next utterance may already have started.)
            guard phase == .hearing, !(confirmed.isEmpty && hypothesis.isEmpty) else {
                reset()
                return []
            }
            return [closeOut()]
        }
    }

    /// Advance time; may finalize or drop the current utterance.
    public mutating func tick(at now: TimeInterval) -> [AssemblerOutput] {
        guard phase == .hearing, let last = lastActivity, let start = startedAt else { return [] }

        if now - start >= policy.maxUtteranceDuration {
            return [closeOut()]
        }
        guard !speechActive else { return [] }
        let quiet = now - last

        if hypothesis.isEmpty {
            guard quiet >= policy.trailingSilence else { return [] }
            if confirmed.isEmpty {
                reset()  // hypothesis retracted to nothing
                return []
            }
            return [closeOut()]
        }
        if quiet >= policy.unconfirmedTailTimeout {
            return [closeOut()]
        }
        return []
    }

    /// The input stream ended: finalize stable text if nothing is pending.
    public mutating func finish() -> [AssemblerOutput] {
        guard phase == .hearing, !(confirmed.isEmpty && hypothesis.isEmpty) else {
            reset()
            return []
        }
        return [closeOut()]
    }

    public mutating func reset() {
        phase = .idle
        confirmed = ""
        hypothesis = ""
        language = nil
        lastActivity = nil
        startedAt = nil
    }

    // MARK: - Private

    private mutating func closeOut() -> AssemblerOutput {
        let output: AssemblerOutput
        if hypothesis.isEmpty && !confirmed.isEmpty {
            output = .final(text: confirmed, language: language)
            finalizedHistory = finalizedHistory.isEmpty ? confirmed : finalizedHistory + " " + confirmed
        } else {
            output = .incomplete(partial)
        }
        reset()
        return output
    }

    private mutating func begin(_ now: TimeInterval) {
        if phase == .idle {
            phase = .hearing
            startedAt = now
        }
    }

    private mutating func touch(_ now: TimeInterval) {
        lastActivity = now
    }

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.lowercased().hasPrefix(prefix.lowercased())
    }
}
