import AppKit
import ApplicationServices

/// Accessibility (TCC) permission checks. Flow can only ask; macOS grants it
/// (spec 02 §14: never bypass TCC).
public enum AccessibilityPermission {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt directing the user to System Settings, if not yet trusted.
    @discardableResult
    public static func requestWithPrompt() -> Bool {
        // String value of kAXTrustedCheckOptionPrompt (avoids a non-Sendable global in Swift 6).
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens System Settings › Privacy & Security › Accessibility.
    @MainActor
    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
