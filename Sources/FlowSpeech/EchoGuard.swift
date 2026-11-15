import FlowCore
import Foundation

/// Keeps Flow from treating its own speech, picked up by the microphone, as a command.
///
/// Flow has no acoustic echo cancellation, so the policy is **half-duplex**:
/// - Speech that *started while Flow was talking* is dropped, except stop/cancel
///   (barge-in is limited to interrupting).
/// - A stop/cancel heard while Flow talks is dropped only if Flow's own sentence
///   contains that word and the user didn't address Flow by name ("Flow, stop" always works).
/// - Speech that started just after Flow finished (within `tail`) is dropped if it
///   repeats Flow's words; otherwise it is a real answer.
public struct EchoGuard: Sendable {
    public enum Decision: Sendable, Equatable {
        case accept
        /// A stop/cancel: accept it and stop speaking at once.
        case acceptAndInterrupt
        case reject(Reason)
    }

    public enum Reason: String, Sendable, Equatable {
        /// The words match what Flow just said.
        case ownSpeech = "own_speech"
        /// The user spoke while Flow was talking; only stop/cancel are accepted then.
        case spokeDuringPrompt = "spoke_during_prompt"
    }

    struct Interval {
        let text: String
        let words: Set<String>
        let start: Date
        var end: Date?
    }

    /// After Flow stops talking, the recognizer can still deliver its words for about a
    /// segment's worth of time (VAD release 0.4 s + hold 0.6 s + flush).
    public var tail: TimeInterval
    /// Fraction of the utterance's words found in Flow's speech above which it is an echo.
    public var echoOverlap: Double
    /// Used when the recognizer did not report when the speech began.
    public var secondsPerWord: TimeInterval
    public var endpointDelay: TimeInterval
    /// Recognizer delay before the first partial words of an utterance are reported.
    public var partialLatency: TimeInterval

    private var intervals: [Interval] = []

    public init(tail: TimeInterval = 1.2, echoOverlap: Double = 0.6, secondsPerWord: TimeInterval = 0.35,
                endpointDelay: TimeInterval = 1.0, partialLatency: TimeInterval = 0.3) {
        self.tail = tail
        self.echoOverlap = echoOverlap
        self.secondsPerWord = secondsPerWord
        self.endpointDelay = endpointDelay
        self.partialLatency = partialLatency
    }

    public var isSpeaking: Bool { intervals.last.map { $0.end == nil } ?? false }

    public mutating func speechStarted(_ text: String, at time: Date) {
        if let last = intervals.indices.last, intervals[last].end == nil { intervals[last].end = time }
        intervals.append(Interval(text: text, words: Set(Self.words(text)), start: time, end: nil))
        if intervals.count > 6 { intervals.removeFirst(intervals.count - 6) }
    }

    public mutating func speechEnded(at time: Date) {
        if let last = intervals.indices.last, intervals[last].end == nil { intervals[last].end = time }
    }

    public func decide(_ utterance: String, heardFrom: Date?, finalizedAt: Date) -> Decision {
        let words = Self.words(utterance)
        let began = heardFrom ?? finalizedAt.addingTimeInterval(-(Double(max(words.count, 1)) * secondsPerWord + endpointDelay))
        let control = Self.isStopOrCancel(utterance)

        // Flow speech that overlaps [began, finalizedAt] (or ended within `tail` before it began).
        let overlapping = intervals.filter { i in
            i.start <= finalizedAt && (i.end ?? .distantFuture).addingTimeInterval(tail) >= began
        }
        guard !overlapping.isEmpty else { return control ? .acceptAndInterrupt : .accept }
        let latency = heardFrom == nil ? 0 : partialLatency
        let startedDuringSpeech = overlapping.contains { i in
            i.start <= began && began <= (i.end ?? .distantFuture).addingTimeInterval(latency)
        }
        let spokenWords = overlapping.reduce(into: Set<String>()) { $0.formUnion($1.words) }

        if control {
            let addressed = words.first == "flow"
            let controlWords = Set(words).subtracting(["flow"])
            if !addressed, !controlWords.isEmpty, controlWords.isSubset(of: spokenWords) { return .reject(.ownSpeech) }
            return .acceptAndInterrupt
        }
        if startedDuringSpeech { return .reject(.spokeDuringPrompt) }
        // The recognizer heard this begin after Flow went quiet: it cannot be Flow's audio,
        // even if it repeats Flow's words ("Which Sarah? …" → "Sarah Chen").
        if let heardFrom, overlapping.allSatisfy({ ($0.end ?? .distantFuture).addingTimeInterval(partialLatency) < heardFrom }) {
            return .accept
        }
        let matched = words.filter { spokenWords.contains($0) }.count
        if !words.isEmpty, Double(matched) / Double(words.count) >= echoOverlap { return .reject(.ownSpeech) }
        return .accept
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func isStopOrCancel(_ text: String) -> Bool {
        guard let c = DeterministicRouter.route(text)?.control else { return false }
        return c == .stop || c == .cancel
    }
}
