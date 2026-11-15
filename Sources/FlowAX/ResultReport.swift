import FlowWindow
import Foundation

extension NavigationResult {
    /// Multi-line, human-readable evidence for the test UI and `flowctl`.
    public var report: String {
        var lines = ["[\(status.rawValue)] \(command.name): \(userMessage)"]
        if let app { lines.append("  app: \(app.name) (pid \(app.pid))") }
        if let target { lines.append("  target: \(target.displayName) [\(target.id)] \(target.frame.compactDescription)") }
        lines += evidence.map { "  \($0)" }
        if let error { lines.append("  error: \(error)") }
        return lines.joined(separator: "\n")
    }
}
