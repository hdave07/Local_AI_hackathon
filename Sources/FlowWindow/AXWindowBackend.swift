import AppKit
import ApplicationServices
import CoreGraphics

/// Real backend: AXUIElement for window state/control, NSWorkspace for launch/activation,
/// CGWindowList for independent bounds evidence. Public APIs only.
@MainActor
public final class AXWindowBackend: WindowBackend {
    private struct Entry {
        let element: AXUIElement
        let app: AppHandle
    }

    private var entries: [WindowID: Entry] = [:]
    private var nextID: UInt64 = 1
    private let messagingTimeout: Float

    /// Last app other than Flow itself to become active. When the user clicks in
    /// Flow's own window, "the active window" still means the app they were using.
    private var lastExternalApp: AppHandle?

    public init(messagingTimeout: Float = 1.0) {
        self.messagingTimeout = messagingTimeout
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            lastExternalApp = Self.handle(front)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.processIdentifier != getpid()
            else { return }
            let handle = Self.handle(app)
            MainActor.assumeIsolated { self?.lastExternalApp = handle }
        }
    }

    // MARK: Permissions

    public func isAccessibilityTrusted() -> Bool { AccessibilityPermission.isTrusted }

    // MARK: Apps

    public func runningApp(bundleID: String) -> AppHandle? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
            .map(Self.handle)
    }

    public func open(bundleID: String) async throws(WindowError) -> AppHandle {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw .appNotInstalled(bundleID)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        let result: AppHandle? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
                continuation.resume(returning: app.map(Self.handle))
            }
        }
        guard let result else { throw .launchFailed(bundleID) }
        return result
    }

    public func activate(_ app: AppHandle) -> Bool {
        NSRunningApplication(processIdentifier: app.pid)?.activate() ?? false
    }

    public func frontmostApp() -> AppHandle? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            return Self.handle(front)
        }
        guard let last = lastExternalApp,
            let app = NSRunningApplication(processIdentifier: last.pid), !app.isTerminated
        else { return nil }
        return last
    }

    nonisolated private static func handle(_ app: NSRunningApplication) -> AppHandle {
        AppHandle(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)")
    }

    // MARK: Windows

    public func windows(of app: AppHandle) throws(WindowError) -> [WindowState] {
        let appElement = applicationElement(app.pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        switch error {
        case .success: break
        case .noValue, .attributeUnsupported: return []
        default: throw map(error, "reading \(app.name) windows")
        }
        let elements = (value as? [AXUIElement]) ?? []
        return elements.compactMap { element in
            let id = identify(element, app: app)
            return try? read(id: id, element: element, app: app)
        }
    }

    public func focusedWindowID(of app: AppHandle) -> WindowID? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            applicationElement(app.pid), kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return identify(value as! AXUIElement, app: app)
    }

    public func state(of id: WindowID) throws(WindowError) -> WindowState {
        guard let entry = entries[id] else { throw .windowGone }
        return try read(id: id, element: entry.element, app: entry.app)
    }

    public func setPosition(_ id: WindowID, _ point: CGPoint) throws(WindowError) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw .axFailure(operation: "position", code: -1) }
        try set(id, kAXPositionAttribute, value, "moving the window")
    }

    public func setSize(_ id: WindowID, _ size: CGSize) throws(WindowError) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw .axFailure(operation: "size", code: -1) }
        try set(id, kAXSizeAttribute, value, "resizing the window")
    }

    public func setMinimized(_ id: WindowID, _ minimized: Bool) throws(WindowError) {
        try set(id, kAXMinimizedAttribute, (minimized ? kCFBooleanTrue : kCFBooleanFalse)!, "minimizing the window")
    }

    public func raise(_ id: WindowID) throws(WindowError) {
        guard let entry = entries[id] else { throw .windowGone }
        let error = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        guard error == .success else { throw map(error, "raising the window") }
    }

    public func close(_ id: WindowID) throws(WindowError) {
        guard let entry = entries[id] else { throw .windowGone }
        var button: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(entry.element, kAXCloseButtonAttribute as CFString, &button)
        guard error == .success, let button, CFGetTypeID(button) == AXUIElementGetTypeID() else {
            throw error == .invalidUIElement ? .windowGone : .axFailure(operation: "finding the close button", code: error.rawValue)
        }
        let press = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        guard press == .success else { throw map(press, "closing the window") }
    }

    public func regularRunningApps() -> [AppHandle] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() && $0.bundleIdentifier != nil }
            .map(Self.handle)
    }

    public func hasSheet(_ id: WindowID) -> Bool {
        guard let entry = entries[id] else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(entry.element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return false }
        return list.contains { child in
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success
                && (role as? String) == kAXSheetRole
        }
    }

    // MARK: Screen and window server

    public func usableScreenFrame() -> CGRect? {
        // NSScreen.screens.first is the primary (menu bar) display, whose AppKit origin is (0,0).
        guard let primary = NSScreen.screens.first else { return nil }
        return WindowGeometry.axFrame(fromAppKit: primary.visibleFrame, primaryScreenHeight: primary.frame.height)
    }

    public func windowServerFrames(pid: pid_t) -> [CGRect] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
    }

    // MARK: Helpers

    private func applicationElement(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    /// Reuses the existing ID when the element is already known (CFEqual), so the
    /// same live window keeps one identity across re-reads.
    private func identify(_ element: AXUIElement, app: AppHandle) -> WindowID {
        if let existing = entries.first(where: { $0.value.app.pid == app.pid && CFEqual($0.value.element, element) }) {
            return existing.key
        }
        let id = WindowID(nextID)
        nextID += 1
        entries[id] = Entry(element: element, app: app)
        return id
    }

    private func read(id: WindowID, element: AXUIElement, app: AppHandle) throws(WindowError) -> WindowState {
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleError == .invalidUIElement {
            entries[id] = nil
            throw .windowGone
        }
        guard roleError == .success else { throw map(roleError, "reading the window") }

        func attribute(_ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func settable(_ name: String) -> Bool {
            var result = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let v = attribute(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &origin)
        }
        if let v = attribute(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &size)
        }
        return WindowState(
            id: id, app: app,
            title: attribute(kAXTitleAttribute) as? String ?? "",
            frame: CGRect(origin: origin, size: size),
            isStandard: (attribute(kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
            isMinimized: (attribute(kAXMinimizedAttribute) as? Bool) ?? false,
            // "AXFullScreen" has no public constant; it is the documented attribute name used by AppKit windows.
            isFullScreen: (attribute("AXFullScreen") as? Bool) ?? false,
            canMove: settable(kAXPositionAttribute),
            canResize: settable(kAXSizeAttribute),
            canMinimize: settable(kAXMinimizedAttribute))
    }

    private func set(_ id: WindowID, _ attribute: String, _ value: CFTypeRef, _ operation: String) throws(WindowError) {
        guard let entry = entries[id] else { throw .windowGone }
        let error = AXUIElementSetAttributeValue(entry.element, attribute as CFString, value)
        guard error == .success else { throw map(error, operation) }
    }

    private func map(_ error: AXError, _ operation: String) -> WindowError {
        switch error {
        case .apiDisabled: .accessibilityNotTrusted
        case .invalidUIElement: .windowGone
        default: .axFailure(operation: operation, code: error.rawValue)
        }
    }
}
