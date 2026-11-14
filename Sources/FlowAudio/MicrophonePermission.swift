import AVFoundation
import Foundation

public enum MicrophoneAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Abstracts macOS TCC microphone consent so the gate is testable. Implementations
/// may only *ask* the system; Flow never bypasses consent (PRD §9, spec 02 §14).
public protocol MicrophonePermissionProviding: Sendable {
    func status() -> MicrophoneAuthorization
    /// Shows the system prompt (only meaningful when `.notDetermined`). Returns whether access was granted.
    func requestAccess() async -> Bool
    func hasInputDevice() -> Bool
}

/// Real macOS microphone consent via AVFoundation.
///
/// A packaged app needs `NSMicrophoneUsageDescription` in Info.plist. When run from a
/// terminal, macOS attributes the request to the terminal application.
public struct SystemMicrophonePermission: MicrophonePermissionProviding {
    public init() {}

    public func status() -> MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func hasInputDevice() -> Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
}

public enum MicrophoneGate {
    /// Ensures microphone access before any capture starts. Prompts once if undetermined;
    /// otherwise reports the existing decision without re-prompting.
    public static func ensureAccess(_ permission: any MicrophonePermissionProviding) async throws(AudioError) {
        switch permission.status() {
        case .authorized:
            break
        case .denied:
            throw .microphoneDenied
        case .restricted:
            throw .microphoneRestricted
        case .notDetermined:
            guard await permission.requestAccess() else { throw .microphoneDenied }
        }
        guard permission.hasInputDevice() else { throw .noInputDevice }
    }
}
