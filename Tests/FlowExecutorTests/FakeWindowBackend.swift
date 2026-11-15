// Copied from the module's own test target (test targets cannot import each other).
import CoreGraphics
import FlowCore
@testable import FlowWindow

/// In-memory window system for controller unit tests.
@MainActor
final class FakeWindowBackend: WindowBackend {
    var trusted = true
    var installed: Set<String> = Set(KnownApp.allCases.map(\.bundleIdentifier))
    var running: [String: AppHandle] = [:]
    var front: AppHandle?
    var windows: [WindowID: WindowState] = [:]
    var order: [WindowID] = []
    var focused: [pid_t: WindowID] = [:]
    var screen: CGRect? = CGRect(x: 0, y: 30, width: 1352, height: 769)
    var minimumSize: [WindowID: CGSize] = [:]
    var ignoresChanges: Set<WindowID> = []
    var openActivates = true
    var openCreatesWindowFor: [String: CGRect] = [:]
    /// Windows AX no longer lists (Stage Manager) but whose element is still valid.
    var unlisted: Set<WindowID> = []
    /// Number of minimize requests to accept-then-drop (Stage Manager transition).
    var dropMinimizeRequests = 0
    private(set) var mutations = 0
    private var nextID: UInt64 = 100
    private var nextPID: pid_t = 500

    @discardableResult
    func launch(_ app: KnownApp) -> AppHandle {
        if let existing = running[app.bundleIdentifier] { return existing }
        let handle = AppHandle(pid: nextPID, bundleID: app.bundleIdentifier, name: app.rawValue)
        nextPID += 1
        running[app.bundleIdentifier] = handle
        return handle
    }

    @discardableResult
    func addWindow(
        _ app: KnownApp, _ title: String, _ frame: CGRect, minimized: Bool = false, fullScreen: Bool = false,
        canMove: Bool = true, canResize: Bool = true, standard: Bool = true
    ) -> WindowID {
        let handle = launch(app)
        let id = WindowID(nextID)
        nextID += 1
        windows[id] = WindowState(
            id: id, app: handle, title: title, frame: frame, isStandard: standard, isMinimized: minimized,
            isFullScreen: fullScreen, canMove: canMove, canResize: canResize)
        order.append(id)
        return id
    }

    /// Simulates the user (not Flow) changing a window.
    func userSetFrame(_ id: WindowID, _ frame: CGRect) { windows[id] = windows[id]!.with(frame: frame) }
    func close(_ id: WindowID) { windows[id] = nil; order.removeAll { $0 == id } }

    // MARK: WindowBackend

    func isAccessibilityTrusted() -> Bool { trusted }
    func runningApp(bundleID: String) -> AppHandle? { running[bundleID] }

    func open(bundleID: String) async throws(WindowError) -> AppHandle {
        guard installed.contains(bundleID) else { throw .appNotInstalled(bundleID) }
        let app = KnownApp.allCases.first { $0.bundleIdentifier == bundleID }!
        let handle = launch(app)
        if let frame = openCreatesWindowFor[bundleID], !order.contains(where: { windows[$0]?.app == handle }) {
            addWindow(app, "New", frame)
        }
        if openActivates { front = handle }
        return handle
    }

    func activate(_ app: AppHandle) -> Bool { front = app; return true }
    func frontmostApp() -> AppHandle? { front }

    func windows(of app: AppHandle) throws(WindowError) -> [WindowState] {
        order.filter { !unlisted.contains($0) }.compactMap { windows[$0] }.filter { $0.app == app }
    }

    func focusedWindowID(of app: AppHandle) -> WindowID? { focused[app.pid] }

    func state(of id: WindowID) throws(WindowError) -> WindowState {
        guard let w = windows[id] else { throw .windowGone }
        return w
    }

    func setPosition(_ id: WindowID, _ point: CGPoint) throws(WindowError) {
        guard let w = windows[id] else { throw .windowGone }
        mutations += 1
        guard !ignoresChanges.contains(id) else { return }
        windows[id] = w.with(frame: CGRect(origin: point, size: w.frame.size))
    }

    func setSize(_ id: WindowID, _ size: CGSize) throws(WindowError) {
        guard let w = windows[id] else { throw .windowGone }
        mutations += 1
        guard !ignoresChanges.contains(id) else { return }
        let minimum = minimumSize[id] ?? .zero
        let clamped = CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
        windows[id] = w.with(frame: CGRect(origin: w.frame.origin, size: clamped))
    }

    func setMinimized(_ id: WindowID, _ minimized: Bool) throws(WindowError) {
        guard let w = windows[id] else { throw .windowGone }
        mutations += 1
        if dropMinimizeRequests > 0 { dropMinimizeRequests -= 1; return }
        windows[id] = w.with(minimized: minimized)
    }

    func raise(_ id: WindowID) throws(WindowError) {
        guard windows[id] != nil else { throw .windowGone }
    }

    func usableScreenFrame() -> CGRect? { screen }

    func windowServerFrames(pid: pid_t) -> [CGRect] {
        windows.values.filter { $0.app.pid == pid && !$0.isMinimized }.map(\.frame)
    }
}

extension WindowState {
    func with(frame: CGRect? = nil, minimized: Bool? = nil) -> WindowState {
        WindowState(
            id: id, app: app, title: title, frame: frame ?? self.frame, isStandard: isStandard,
            isMinimized: minimized ?? isMinimized, isFullScreen: isFullScreen, canMove: canMove,
            canResize: canResize, canMinimize: canMinimize)
    }
}

@MainActor
func makeController(_ backend: FakeWindowBackend) -> WindowController {
    var configuration = WindowController.Configuration()
    configuration.settleTimeout = .milliseconds(30)
    configuration.activationTimeout = .milliseconds(30)
    configuration.pollInterval = .milliseconds(1)
    return WindowController(backend: backend, configuration: configuration)
}
