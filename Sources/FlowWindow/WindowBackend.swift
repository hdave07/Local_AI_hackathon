import CoreGraphics
import Foundation

/// Narrow interface over macOS app/window services so controller logic is unit-testable.
/// `AXWindowBackend` is the real implementation; tests use a fake.
@MainActor
public protocol WindowBackend: AnyObject {
    func isAccessibilityTrusted() -> Bool
    func runningApp(bundleID: String) -> AppHandle?
    /// Launch, or re-open and activate if already running (never a duplicate instance).
    func open(bundleID: String) async throws(WindowError) -> AppHandle
    func activate(_ app: AppHandle) -> Bool
    func frontmostApp() -> AppHandle?
    /// All AX windows of the app (callers filter on `isStandard`).
    func windows(of app: AppHandle) throws(WindowError) -> [WindowState]
    func focusedWindowID(of app: AppHandle) -> WindowID?
    /// Re-reads a window. Throws `.windowGone` if it no longer exists.
    func state(of id: WindowID) throws(WindowError) -> WindowState
    func setPosition(_ id: WindowID, _ point: CGPoint) throws(WindowError)
    func setSize(_ id: WindowID, _ size: CGSize) throws(WindowError)
    func setMinimized(_ id: WindowID, _ minimized: Bool) throws(WindowError)
    func raise(_ id: WindowID) throws(WindowError)
    /// Presses the window's own close button (never quits the app, never answers a sheet).
    func close(_ id: WindowID) throws(WindowError)
    /// The window shows a sheet (e.g. "Do you want to save changes?").
    func hasSheet(_ id: WindowID) -> Bool
    /// Usable area of the primary display (excludes menu bar and Dock), AX coordinates.
    func usableScreenFrame() -> CGRect?
    /// On-screen window bounds for a process from the window server, AX-compatible coordinates.
    func windowServerFrames(pid: pid_t) -> [CGRect]
}

public extension WindowBackend {
    func close(_ id: WindowID) throws(WindowError) { throw .axFailure(operation: "closing the window", code: -1) }
    func hasSheet(_ id: WindowID) -> Bool { false }
}
