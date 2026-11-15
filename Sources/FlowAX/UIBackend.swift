import CoreGraphics
import FlowCore
import FlowWindow
import Foundation

/// Scroll state used to verify that a scroll did something.
public struct ScrollPosition: Sendable, Equatable {
    /// Vertical scroll bar value 0...1 when the app exposes one.
    public let vertical: Double?
    /// Frames of the first few visible children, as a fallback signal.
    public let contentMarker: [CGRect]

    public init(vertical: Double?, contentMarker: [CGRect]) {
        self.vertical = vertical
        self.contentMarker = contentMarker
    }
}

/// Narrow interface over Accessibility so navigation logic is testable with a fake.
/// `AXUIBackend` is the real implementation.
@MainActor
public protocol UIBackend: AnyObject {
    func isAccessibilityTrusted() -> Bool
    func resolveApp(_ scope: AppScope) throws(NavigationError) -> AppHandle
    /// Brings the app forward; returns whether it is frontmost afterwards.
    func bringToFront(_ app: AppHandle) async -> Bool
    /// Inspects the app's focused (or main) window. Assigns a new epoch.
    func snapshot(of app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot
    /// Like `snapshot`, but its elements are not retained (epoch -1). Used for verification
    /// polling so it never evicts snapshots that numbered targets still refer to.
    func observe(_ app: AppHandle, limits: SnapshotLimits) throws(NavigationError) -> UISnapshot
    /// Re-reads the same underlying element. Throws `.targetGone` if it no longer exists
    /// or its snapshot has been discarded.
    func refresh(_ id: ElementID) throws(NavigationError) -> UIElementInfo
    func press(_ id: ElementID) throws(NavigationError)
    func setFocused(_ id: ElementID) throws(NavigationError)
    func setSelected(_ id: ElementID) throws(NavigationError)
    func scroll(_ id: ElementID, _ direction: ScrollDirection) throws(NavigationError)
    func scrollPosition(_ id: ElementID) -> ScrollPosition?
    /// Whether the app's focused UI element is this element.
    func isFocusedElement(_ id: ElementID, in app: AppHandle) -> Bool
}
