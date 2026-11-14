import CoreGraphics
import Foundation

extension CGRect {
    /// "x,y wxh" in points, for logs and the test UI.
    public var compactDescription: String {
        "\(Int(minX)),\(Int(minY)) \(Int(width))×\(Int(height))"
    }
}

extension WindowActionResult {
    /// Multi-line, human-readable evidence for the test UI and `flowctl`.
    public var report: String {
        var lines = ["[\(status.rawValue)] \(command.name): \(userMessage)"]
        for (index, state) in observed.enumerated() {
            var line = "  \(state.displayName) [\(state.id)]"
            if index < before.count { line += " before \(before[index].compactDescription)" }
            if index < expected.count { line += " expected \(expected[index].compactDescription)" }
            line += " observed \(state.frame.compactDescription)"
            if state.isMinimized { line += " (minimized)" }
            lines.append(line)
        }
        if let windowServerConfirmed { lines.append("  window server agrees: \(windowServerConfirmed)") }
        if let error { lines.append("  error: \(error)") }
        if let undoToken { lines.append("  undo available (\(undoToken.uuidString.prefix(8)))") }
        return lines.joined(separator: "\n")
    }
}
