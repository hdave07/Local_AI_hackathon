import Foundation

/// Energy-based voice-activity detector with hysteresis.
///
/// Argmax Pro 3.1.8's streaming API gates decoding on input energy
/// (`StreamTranscriptionMode.voiceTriggered`) but does not emit VAD events, so Flow
/// derives start/end transitions itself from the same audio chunks. The Argmax
/// adapter feeds the SDK's normalized relative energy and silence threshold so both
/// agree. Speech starts after `attack` seconds at/above threshold and ends after
/// `release` seconds below it.
public struct EnergyVoiceActivityDetector: Sendable {
    public let threshold: Float
    public let sampleRate: Double
    public let attack: TimeInterval
    public let release: TimeInterval

    public private(set) var isSpeech = false
    private var aboveFor: TimeInterval = 0
    private var belowFor: TimeInterval = 0

    public init(threshold: Float, sampleRate: Double = 16_000, attack: TimeInterval = 0.05, release: TimeInterval = 0.4) {
        self.threshold = threshold
        self.sampleRate = sampleRate
        self.attack = attack
        self.release = release
    }

    /// Feed one chunk, measuring its RMS level; returns a transition if one occurred.
    public mutating func process(_ samples: [Float]) -> VoiceActivity? {
        guard !samples.isEmpty else { return nil }
        return process(level: Self.rms(samples), duration: Double(samples.count) / sampleRate)
    }

    /// Feed a precomputed level for a chunk of `duration` seconds. Use this when the
    /// threshold is defined on another scale (e.g. the SDK's normalized relative energy).
    public mutating func process(level: Float, duration: TimeInterval) -> VoiceActivity? {
        guard duration > 0 else { return nil }
        if level >= threshold {
            aboveFor += duration
            belowFor = 0
            if !isSpeech && aboveFor >= attack {
                isSpeech = true
                return .speechStarted
            }
        } else {
            belowFor += duration
            aboveFor = 0
            if isSpeech && belowFor >= release {
                isSpeech = false
                return .speechEnded
            }
        }
        return nil
    }

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}
