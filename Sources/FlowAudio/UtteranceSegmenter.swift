import Foundation

/// Decides where one spoken utterance ends in a continuous audio stream.
///
/// Why it exists: Argmax Pro 3.1.8 + Parakeet confirms the final words of an utterance
/// only when its input stream ends; during continued silence it never confirms
/// (measured with 8 s of trailing silence in every `StreamTranscriptionMode`). Flow
/// therefore ends each recognizer stream itself once speech has stopped, which makes
/// the SDK flush and *confirm* the text. Actions still use confirmed text only.
public struct UtteranceSegmenter: Sendable {
    public struct Policy: Sendable, Equatable {
        /// Extra quiet time after the VAD reports end of speech before cutting.
        public var hold: TimeInterval
        /// Force a cut for very long speech so text is not held indefinitely.
        public var maxSegment: TimeInterval
        /// Recycle a segment that has heard no speech, bounding recognizer buffers.
        public var maxIdle: TimeInterval

        public init(hold: TimeInterval = 0.3, maxSegment: TimeInterval = 30, maxIdle: TimeInterval = 20) {
            self.hold = hold
            self.maxSegment = maxSegment
            self.maxIdle = maxIdle
        }
    }

    public struct Step: Sendable, Equatable {
        public var activity: VoiceActivity?
        /// End the current recognizer stream after this chunk.
        public var cut: Bool

        public init(activity: VoiceActivity?, cut: Bool) {
            self.activity = activity
            self.cut = cut
        }
    }

    public let policy: Policy
    public private(set) var vad: EnergyVoiceActivityDetector
    private var heardSpeech = false
    private var sinceSpeechEnded: TimeInterval?
    private var length: TimeInterval = 0

    public init(vad: EnergyVoiceActivityDetector, policy: Policy = Policy()) {
        self.vad = vad
        self.policy = policy
    }

    public mutating func process(level: Float, duration: TimeInterval) -> Step {
        let activity = vad.process(level: level, duration: duration)
        length += duration
        switch activity {
        case .speechStarted:
            heardSpeech = true
            sinceSpeechEnded = nil
        case .speechEnded:
            sinceSpeechEnded = 0
        case nil:
            if let since = sinceSpeechEnded, !vad.isSpeech { sinceSpeechEnded = since + duration }
        }

        let endOfUtterance = heardSpeech && !vad.isSpeech && (sinceSpeechEnded ?? -1) >= policy.hold
        let tooLong = heardSpeech && length >= policy.maxSegment
        let idle = !heardSpeech && length >= policy.maxIdle
        let cut = endOfUtterance || tooLong || idle
        if cut {
            heardSpeech = vad.isSpeech  // a forced cut mid-speech continues into the next segment
            sinceSpeechEnded = nil
            length = 0
        }
        return Step(activity: activity, cut: cut)
    }
}
