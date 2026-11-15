import CoreGraphics
import FlowCore
import Foundation

/// Executes typed window commands with the spec 02 §7 procedure:
/// resolve → check settable attributes → snapshot → execute → re-read → compare
/// within tolerance → report `completed` only when verified.
@MainActor
public final class WindowController {
    public struct Configuration: Sendable {
        public var tolerance: CGFloat = 2
        public var settleTimeout: Duration = .milliseconds(1500)
        public var activationTimeout: Duration = .seconds(12)
        public var pollInterval: Duration = .milliseconds(50)
        public var resizeStep = WindowGeometry.defaultStep
        public var maxUndoDepth = 20

        public init() {}
    }

    struct FrameChange: Equatable {
        let ref: WindowRef
        let before: CGRect
        let after: CGRect
    }

    enum UndoEntry: Equatable {
        case frames(token: UUID, [FrameChange])
        case minimized(token: UUID, WindowRef)
        case restored(token: UUID, WindowRef)
    }

    public let backend: WindowBackend
    public let configuration: Configuration
    private(set) var undoStack: [UndoEntry] = []

    public init(backend: WindowBackend, configuration: Configuration = Configuration()) {
        self.backend = backend
        self.configuration = configuration
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    /// Standard windows of an app, for display and disambiguation.
    public func listWindows(_ app: KnownApp) throws(WindowError) -> [WindowState] {
        guard backend.isAccessibilityTrusted() else { throw .accessibilityNotTrusted }
        guard let handle = backend.runningApp(bundleID: app.bundleIdentifier) else { throw .appNotRunning(app.rawValue) }
        return try backend.windows(of: handle).filter(\.isStandard)
    }

    /// Standard windows of every running app (for "show me my open windows"), app by app.
    public func listAllWindows() throws(WindowError) -> [(app: AppHandle, windows: [WindowState])] {
        guard backend.isAccessibilityTrusted() else { throw .accessibilityNotTrusted }
        return backend.regularRunningApps().compactMap { app in
            guard let ws = try? backend.windows(of: app).filter(\.isStandard), !ws.isEmpty else { return nil }
            return (app, ws)
        }
    }

    public func perform(_ command: WindowCommand) async -> WindowActionResult {
        guard backend.isAccessibilityTrusted() else { return failure(command, .accessibilityNotTrusted) }
        do throws(WindowError) {
            switch command {
            case .activate(let app):
                return try await activate(app)
            case .move(let selector, let position):
                return try await move(selector, position, command)
            case .resize(let selector, let change):
                return try await resize(selector, change, command)
            case .tile(let left, let right):
                return try await tile(left, right, command)
            case .minimize(let selector):
                return try await setMinimized(selector, true, command)
            case .restore(let selector):
                return try await setMinimized(selector, false, command)
            case .close(let selector):
                return try await close(selector, command)
            case .undo:
                return try await undo()
            }
        } catch {
            return failure(command, error)
        }
    }

    // MARK: Activate

    private func activate(_ app: KnownApp) async throws(WindowError) -> WindowActionResult {
        let command = WindowCommand.activate(app)
        let handle = try await backend.open(bundleID: app.bundleIdentifier)
        var windows: [WindowState] = []
        let verified = await waitUntil(configuration.activationTimeout) {
            windows = ((try? backend.windows(of: handle)) ?? []).filter { $0.isStandard && !$0.isMinimized }
            return backend.frontmostApp()?.pid == handle.pid && !windows.isEmpty
        }
        let front = backend.frontmostApp()?.pid == handle.pid
        if verified {
            return result(command, .completed, targets: windows, observed: windows,
                          message: "\(handle.name) is in front.")
        }
        if front {
            return result(command, .partiallyCompleted, observed: windows,
                          message: "\(handle.name) is in front but has no open window.")
        }
        return result(command, .unverified, observed: windows,
                      message: "macOS didn't confirm \(handle.name) came to the front.")
    }

    // MARK: Move / resize / tile

    private func move(_ selector: WindowSelector, _ position: WindowPosition, _ command: WindowCommand)
        async throws(WindowError) -> WindowActionResult
    {
        let window = try resolve(selector, minimized: false)
        if let reason = unsupportedReason(window, needsResize: position != .center) {
            return unsupported(command, window, reason)
        }
        guard let screen = backend.usableScreenFrame() else { throw .noScreen }
        let target = WindowGeometry.targetFrame(for: position, current: window.frame, screen: screen)
        return try await applyFrames(command, [(window, target)], recordUndo: true,
                                     success: "Moved \(window.displayName) to \(position.rawValue).")
    }

    private func resize(_ selector: WindowSelector, _ change: ResizeChange, _ command: WindowCommand)
        async throws(WindowError) -> WindowActionResult
    {
        let window = try resolve(selector, minimized: false)
        if let reason = unsupportedReason(window, needsResize: true) {
            return unsupported(command, window, reason)
        }
        guard let screen = backend.usableScreenFrame() else { throw .noScreen }
        let target = WindowGeometry.resized(window.frame, change: change, screen: screen, step: configuration.resizeStep)
        if WindowGeometry.approximatelyEqual(target, window.frame, tolerance: configuration.tolerance) {
            return unsupported(command, window, .atSizeLimit)
        }
        return try await applyFrames(command, [(window, target)], recordUndo: true,
                                     success: "Made \(window.displayName) \(change.rawValue).")
    }

    private func tile(_ left: KnownApp, _ right: KnownApp, _ command: WindowCommand)
        async throws(WindowError) -> WindowActionResult
    {
        guard left != right else {
            return result(command, .unsupported, unsupported: .sameApp, message: UnsupportedReason.sameApp.rawValue)
        }
        let l = try resolve(.app(left), minimized: false)
        let r = try resolve(.app(right), minimized: false)
        for window in [l, r] {
            if let reason = unsupportedReason(window, needsResize: true) { return unsupported(command, window, reason) }
        }
        guard let screen = backend.usableScreenFrame() else { throw .noScreen }
        // Bring both forward so the result is visible (spec WIN-01).
        _ = backend.activate(r.app)
        _ = backend.activate(l.app)
        try? backend.raise(r.id)
        try? backend.raise(l.id)
        let leftTarget = WindowGeometry.targetFrame(for: .leftHalf, current: l.frame, screen: screen)
        let rightTarget = WindowGeometry.targetFrame(for: .rightHalf, current: r.frame, screen: screen)
        let success = "Tiled \(l.app.name) left and \(r.app.name) right."
        let first = try await applyFrames(command, [(l, leftTarget), (r, rightTarget)], recordUndo: true, success: success)

        guard first.status == .partiallyCompleted, first.observed.count == 2,
            let split = WindowGeometry.adjustedSplit(
                leftObserved: first.observed[0].frame.size, rightObserved: first.observed[1].frame.size,
                leftTarget: leftTarget, rightTarget: rightTarget, screen: screen, tolerance: configuration.tolerance)
        else { return first }

        // Replace the first pass's undo entry so one undo returns to the original frames.
        if let token = first.undoToken, case .frames(let last, _) = undoStack.last, last == token {
            undoStack.removeLast()
        }
        return try await applyFrames(
            command, [(first.observed[0], split.left), (first.observed[1], split.right)], recordUndo: true,
            baseline: [l, r],
            partial: "\(l.app.name) and \(r.app.name) can't both fit side by side on this display at their minimum widths; they overlap slightly.",
            success: "Tiled \(l.app.name) left and \(r.app.name) right; split adjusted for \(first.observed[0].frame.width > leftTarget.width + configuration.tolerance ? l.app.name : r.app.name)'s minimum width.")
    }

    /// `baseline` overrides the "before" states (used when a command applies in two passes).
    private func applyFrames(
        _ command: WindowCommand, _ changes: [(WindowState, CGRect)], recordUndo: Bool,
        baseline: [WindowState]? = nil, partial: String? = nil, success: String
    ) async throws(WindowError) -> WindowActionResult {
        let originals = baseline ?? changes.map(\.0)
        for (window, target) in changes {
            // Position, size, position: size changes near screen edges can shift the origin.
            try backend.setPosition(window.id, target.origin)
            try backend.setSize(window.id, target.size)
            try backend.setPosition(window.id, target.origin)
        }

        var observed: [WindowState] = []
        let tolerance = configuration.tolerance
        let verified = await waitUntil(configuration.settleTimeout) {
            observed = changes.compactMap { try? backend.state(of: $0.0.id) }
            return observed.count == changes.count
                && zip(observed, changes).allSatisfy { WindowGeometry.approximatelyEqual($0.frame, $1.1, tolerance: tolerance) }
        }
        guard observed.count == changes.count else { throw .windowGone }

        let moved = zip(observed, originals).map { !WindowGeometry.approximatelyEqual($0.frame, $1.frame, tolerance: tolerance) }
        var token: UUID?
        if recordUndo, moved.contains(true) {
            let entries = zip(observed, originals).map { FrameChange(ref: WindowRef($1), before: $1.frame, after: $0.frame) }
            token = UUID()
            push(.frames(token: token!, entries))
        }

        let status: ActionStatus
        let message: String
        if verified {
            status = .completed
            message = success
        } else if moved.contains(true) {
            status = .partiallyCompleted
            message = partial ?? "The window moved but didn't reach the exact size; the app may limit it."
        } else {
            status = .failed
            message = "The window didn't change."
        }
        // Independent evidence from the window server, which can lag AX during
        // Stage Manager transitions; poll briefly rather than sample once.
        let serverConfirmed = await waitUntil(configuration.settleTimeout) {
            observed.allSatisfy { state in
                backend.windowServerFrames(pid: state.app.pid)
                    .contains { WindowGeometry.approximatelyEqual($0, state.frame, tolerance: tolerance) }
            }
        }
        return result(
            command, status, targets: originals, before: originals.map(\.frame), observed: observed,
            expected: changes.map(\.1), windowServerConfirmed: serverConfirmed, undo: token, message: message)
    }

    // MARK: Minimize / restore

    private func setMinimized(_ selector: WindowSelector, _ minimize: Bool, _ command: WindowCommand)
        async throws(WindowError) -> WindowActionResult
    {
        let window = try resolve(selector, minimized: !minimize)
        guard window.canMinimize else { return unsupported(command, window, .notMinimizable) }
        return try await applyMinimized(command, window, minimize, recordUndo: true)
    }

    private func applyMinimized(_ command: WindowCommand, _ window: WindowState, _ minimize: Bool, recordUndo: Bool)
        async throws(WindowError) -> WindowActionResult
    {
        var observed: WindowState?
        var verified = false
        // Setting AXMinimized is idempotent. During a Stage Manager / activation
        // transition macOS can accept the request (AX success) and then drop it,
        // so re-issue once (spec 02 §13 bounded retry for idempotent operations).
        for _ in 0..<2 where !verified {
            try backend.setMinimized(window.id, minimize)
            verified = await waitUntil(configuration.settleTimeout) {
                observed = try? backend.state(of: window.id)
                return observed?.isMinimized == minimize
            }
        }
        guard let observed else { throw .windowGone }
        guard verified else {
            return result(command, .failed, targets: [window], observed: [observed],
                          message: "macOS didn't confirm the window was \(minimize ? "minimized" : "restored").")
        }
        var token: UUID?
        if recordUndo {
            token = UUID()
            push(minimize ? .minimized(token: token!, WindowRef(window)) : .restored(token: token!, WindowRef(window)))
        }
        return result(command, .completed, targets: [window], before: [window.frame], observed: [observed], undo: token,
                      message: "\(minimize ? "Minimized" : "Restored") \(window.displayName).")
    }

    // MARK: Close

    /// Presses the window's close button and verifies it went away. If the app asks to save
    /// changes, Flow stops there: the sheet is the user's decision (never "Don't Save").
    /// Closing is not undoable and never quits the app.
    private func close(_ selector: WindowSelector, _ command: WindowCommand) async throws(WindowError) -> WindowActionResult {
        let window = try resolve(selector, minimized: false)
        try backend.close(window.id)
        var gone = false
        var sheet = false
        _ = await waitUntil(configuration.settleTimeout) {
            if backend.hasSheet(window.id) { sheet = true; return true }
            do throws(WindowError) {
                _ = try backend.state(of: window.id)
                return false
            } catch {
                gone = error == .windowGone
                return gone
            }
        }
        // A window that has left the app's window list is closed even if its element lingers.
        if !gone, !sheet, let app = backend.runningApp(bundleID: window.app.bundleID),
           let remaining = try? backend.windows(of: app), !remaining.contains(where: { $0.id == window.id }) {
            gone = true
        }
        if gone {
            return result(command, .completed, targets: [window], before: [window.frame],
                          message: "Closed \(window.displayName). \(window.app.name) is still open.")
        }
        if sheet {
            return result(command, .partiallyCompleted, targets: [window], observed: [window],
                          message: "\(window.app.name) is asking whether to save changes. I didn't answer it; that's up to you.")
        }
        return result(command, .unverified, targets: [window], observed: [window],
                      message: "I pressed close, but \(window.displayName) is still open.")
    }

    // MARK: Undo

    private func undo() async throws(WindowError) -> WindowActionResult {
        guard let entry = undoStack.popLast() else { throw .nothingToUndo }
        do throws(WindowError) {
            switch entry {
            case .frames(_, let changes):
                var current: [(WindowState, CGRect)] = []
                for change in changes {
                    let state = try backend.state(of: change.ref.id)
                    guard !state.isMinimized,
                        WindowGeometry.approximatelyEqual(state.frame, change.after, tolerance: configuration.tolerance)
                    else { throw .changedSinceAction(state.displayName) }
                    current.append((state, change.before))
                }
                return try await applyFrames(.undo, current, recordUndo: false, success: "Restored the previous window position.")

            case .minimized(_, let ref), .restored(_, let ref):
                let wasMinimize = if case .minimized = entry { true } else { false }
                let state = try backend.state(of: ref.id)
                guard state.isMinimized == wasMinimize else { throw .changedSinceAction(state.displayName) }
                return try await applyMinimized(.undo, state, !wasMinimize, recordUndo: false)
            }
        } catch {
            // Stop walking history once reality no longer matches it (PRD §7.6).
            undoStack.removeAll()
            throw error
        }
    }

    private func push(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > configuration.maxUndoDepth { undoStack.removeFirst() }
    }

    // MARK: Resolution (spec 02 §7 target rules)

    func resolve(_ selector: WindowSelector, minimized: Bool) throws(WindowError) -> WindowState {
        let app: AppHandle
        switch selector.target {
        case .active:
            guard let front = backend.frontmostApp() else { throw .noFrontmostApp }
            app = front
        case .app(let known):
            guard let running = backend.runningApp(bundleID: known.bundleIdentifier) else {
                throw .appNotRunning(known.rawValue)
            }
            app = running
        }

        var candidates = try backend.windows(of: app).filter { $0.isStandard && $0.isMinimized == minimized }
        if let title = selector.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            let exact = candidates.filter { $0.title.caseInsensitiveCompare(title) == .orderedSame }
            candidates = exact.isEmpty ? candidates.filter { $0.title.localizedCaseInsensitiveContains(title) } : exact
        }

        switch candidates.count {
        case 0:
            // Under Stage Manager a minimized window can drop out of the app's AX window
            // list while its element stays valid. Fall back to a window Flow itself
            // minimized, re-validated by a fresh read (spec 02 §7 "valid recent reference").
            if minimized, selector.title == nil {
                for case .minimized(_, let ref) in undoStack.reversed() where ref.appBundleID == app.bundleID {
                    if let state = try? backend.state(of: ref.id), state.isMinimized { return state }
                }
            }
            throw .noWindow(app.name)
        case 1:
            return candidates[0]
        default:
            // Verified focus disambiguates same-app windows; a recent Flow reference
            // disambiguates restore. Otherwise ask (spec 02 §7, WIN-04).
            if !minimized, let focused = backend.focusedWindowID(of: app),
                let match = candidates.first(where: { $0.id == focused })
            {
                return match
            }
            if minimized {
                for entry in undoStack.reversed() {
                    if case .minimized(_, let ref) = entry, let match = candidates.first(where: { $0.id == ref.id }) {
                        return match
                    }
                }
            }
            throw .ambiguousWindow(app: app.name, candidates: candidates.map { $0.title.isEmpty ? "untitled" : $0.title })
        }
    }

    private func unsupportedReason(_ window: WindowState, needsResize: Bool) -> UnsupportedReason? {
        if window.isFullScreen { return .fullScreen }
        if !window.canMove { return .notMovable }
        if needsResize && !window.canResize { return .notResizable }
        return nil
    }

    // MARK: Helpers

    private func waitUntil(_ timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            if condition() { return true }
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    private func result(
        _ command: WindowCommand, _ status: ActionStatus, targets: [WindowState] = [], before: [CGRect] = [],
        observed: [WindowState] = [], expected: [CGRect] = [], windowServerConfirmed: Bool? = nil,
        error: WindowError? = nil, unsupported: UnsupportedReason? = nil, undo: UUID? = nil, message: String
    ) -> WindowActionResult {
        WindowActionResult(
            actionID: UUID(), command: command, status: status, targets: targets.map(WindowRef.init),
            before: before, observed: observed, expected: expected, windowServerConfirmed: windowServerConfirmed,
            error: error, unsupportedReason: unsupported, undoToken: undo, userMessage: message, timestamp: Date())
    }

    private func failure(_ command: WindowCommand, _ error: WindowError) -> WindowActionResult {
        result(command, .failed, error: error, message: error.userMessage)
    }

    private func unsupported(_ command: WindowCommand, _ window: WindowState, _ reason: UnsupportedReason) -> WindowActionResult {
        result(command, .unsupported, targets: [window], observed: [window], unsupported: reason,
               message: "Can't do that: \(reason.rawValue).")
    }
}
