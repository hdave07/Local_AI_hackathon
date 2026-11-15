import AVFoundation
import Foundation

public enum SpeechAvailability: Sendable, Equatable {
    case available(voice: String)
    case unavailable(String)
}

public enum SpeechOutcome: Sendable, Equatable {
    case finished
    /// Stopped early (user said "Flow, stop", or newer feedback replaced it).
    case interrupted
    case unavailable(String)
}

/// Local text-to-speech. Implementations never send text off the Mac.
public protocol SpeechOutput: Sendable {
    func availability() async -> SpeechAvailability
    /// Speaks `text`; returns when finished or interrupted.
    func speak(_ text: String) async -> SpeechOutcome
    /// Stops current speech immediately. Safe when silent.
    func stop() async
}

/// macOS system speech via `AVSpeechSynthesizer` (on-device voices only).
///
/// If no voice exists for the language (or the requested voice was removed), it falls back
/// to any installed voice. If there are none, `availability()` reports why and `speak`
/// returns `.unavailable`, so Flow stays usable visually.
public final class SystemSpeechOutput: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let rate: Float
    private let lock = NSLock()
    private var waiting: [ObjectIdentifier: CheckedContinuation<SpeechOutcome, Never>] = [:]

    /// - Parameters:
    ///   - language: BCP-47 language for the default voice.
    ///   - voiceIdentifier: a specific installed voice; ignored if missing.
    ///   - rate: `AVSpeechUtterance` rate (default slightly slower than the system default, for clarity).
    public init(language: String = "en-US", voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.95) {
        voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice.speechVoices().first
        self.rate = rate
        super.init()
        synthesizer.delegate = self
    }

    public func availability() async -> SpeechAvailability {
        guard let voice else { return .unavailable("No speech voice is installed. Add one in System Settings › Accessibility › Spoken Content.") }
        return .available(voice: voice.name)
    }

    public func speak(_ text: String) async -> SpeechOutcome {
        guard let voice else { return .unavailable("No speech voice is installed.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .finished }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = rate
        return await withCheckedContinuation { continuation in
            lock.withLock { waiting[ObjectIdentifier(utterance)] = continuation }
            synthesizer.speak(utterance)
        }
    }

    /// Stops speech and resolves every waiting `speak` as `.interrupted` immediately.
    /// (Live test: on macOS `stopSpeaking` may report `didFinish` rather than `didCancel`, or
    /// nothing for a queued utterance, so the outcome must not depend on which callback fires.)
    public func stop() async {
        let interrupted = lock.withLock { () -> [CheckedContinuation<SpeechOutcome, Never>] in
            defer { waiting.removeAll() }
            return Array(waiting.values)
        }
        synthesizer.stopSpeaking(at: .immediate)
        for c in interrupted { c.resume(returning: .interrupted) }
    }

    // MARK: AVSpeechSynthesizerDelegate

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resume(utterance, .finished)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resume(utterance, .interrupted)
    }

    private func resume(_ utterance: AVSpeechUtterance, _ outcome: SpeechOutcome) {
        let c = lock.withLock { waiting.removeValue(forKey: ObjectIdentifier(utterance)) }
        c?.resume(returning: outcome)
    }
}
