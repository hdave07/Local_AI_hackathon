import Foundation

/// Typed, never-silent speech-pipeline failures (plan 03 §3 "Errors typed, never silent").
public enum AudioError: Error, Sendable, Equatable {
    /// The user (or policy) denied microphone access in System Settings.
    case microphoneDenied
    /// Microphone access is restricted by device management / parental controls.
    case microphoneRestricted
    /// No audio input device is available.
    case noInputDevice
    /// No Argmax runtime API key was provided (`ARGMAX_API_KEY`).
    case licenseMissing
    /// The speech SDK rejected the license or the license could not be activated.
    case licenseRejected(String)
    /// The speech model could not be downloaded or loaded.
    case modelUnavailable(String)
    /// The selected SDK/backend does not provide a requested feature.
    case featureUnavailable(String)
    /// The recognizer failed while running.
    case engineFailed(String)
    case alreadyRunning
    case cancelled

    /// Spec 02 §18 ERR-03: microphone/OS failures cannot promise voice-only recovery.
    public var isRecoverableByVoice: Bool {
        switch self {
        case .microphoneDenied, .microphoneRestricted, .noInputDevice: false
        case .licenseMissing, .licenseRejected, .modelUnavailable, .featureUnavailable: false
        case .engineFailed, .alreadyRunning, .cancelled: true
        }
    }

    /// Concise one-line HUD message (spec 02 §13). Never claims a bypass of macOS consent.
    public var userMessage: String {
        switch self {
        case .microphoneDenied:
            "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone."
        case .microphoneRestricted:
            "Microphone access is restricted on this Mac. An administrator must allow it."
        case .noInputDevice: "No microphone found. Connect or select an input device."
        case .licenseMissing: "Speech recognition isn't set up: the Argmax API key is missing."
        case .licenseRejected: "Speech recognition license couldn't be activated."
        case .modelUnavailable: "The speech model isn't available. Download it while online."
        case .featureUnavailable(let feature): "Speech feature unavailable: \(feature)."
        case .engineFailed: "Speech recognition stopped unexpectedly. Try again."
        case .alreadyRunning: "Already listening."
        case .cancelled: "Stopped listening."
        }
    }
}
