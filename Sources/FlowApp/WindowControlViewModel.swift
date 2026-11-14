import FlowCore
import FlowWindow
import Foundation
import Observation

/// Typed test interface for FlowWindow inside the app. Commands go through the same
/// deterministic parser and controller as `flowctl` and the live tests.
@MainActor
@Observable
final class WindowControlViewModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let input: String
        let status: ActionStatus?
        let text: String
    }

    var command = ""
    private(set) var isRunning = false
    private(set) var isTrusted = AccessibilityPermission.isTrusted
    private(set) var log: [LogEntry] = []

    private let controller: WindowController

    init(controller: WindowController) {
        self.controller = controller
    }

    var canUndo: Bool { controller.canUndo }

    func refreshPermission() { isTrusted = AccessibilityPermission.isTrusted }

    func requestPermission() {
        AccessibilityPermission.requestWithPrompt()
        refreshPermission()
    }

    func openSettings() { AccessibilityPermission.openSystemSettings() }

    func submit() {
        let text = command
        Task { await run(text) }
    }

    func run(_ text: String) async {
        guard !isRunning else { return }
        refreshPermission()
        isRunning = true
        defer { isRunning = false }

        let entry: LogEntry
        do throws(CommandParseError) {
            switch try WindowCommandParser.parse(text) {
            case .window(let command):
                let result = await controller.perform(command)
                entry = LogEntry(input: text, status: result.status, text: result.report)
            case .list(let app):
                entry = list(app, input: text)
            }
        } catch {
            entry = LogEntry(input: text, status: nil, text: error.message)
        }
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast() }
    }

    private func list(_ app: KnownApp, input: String) -> LogEntry {
        do throws(WindowError) {
            let windows = try controller.listWindows(app)
            let lines = windows.isEmpty
                ? ["  (no windows visible to Accessibility)"]
                : windows.map { "  [\($0.id)] \($0.displayName) \($0.frame.compactDescription)\($0.isMinimized ? " (minimized)" : "")" }
            return LogEntry(input: input, status: nil, text: (["\(app.rawValue) windows:"] + lines).joined(separator: "\n"))
        } catch {
            return LogEntry(input: input, status: .failed, text: error.userMessage)
        }
    }
}
