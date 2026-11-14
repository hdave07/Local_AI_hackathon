import FlowCore
import FlowWindow
import Foundation

// Usage: flowctl "activate notes" "move notes left_half" "undo"
// Runs each typed command in order against the real macOS windows and prints
// verified results. Exit code 1 if any command is not `completed`.

@MainActor
func run() async -> Int32 {
    let commands = Array(CommandLine.arguments.dropFirst())
    guard !commands.isEmpty else {
        print("usage: flowctl \"<command>\" [\"<command>\" ...]\n\(WindowCommandParser.usage)")
        return 2
    }
    guard AccessibilityPermission.isTrusted else {
        print("Accessibility permission is not granted to this process (or its parent terminal).")
        print("Grant it in System Settings › Privacy & Security › Accessibility, then retry.")
        AccessibilityPermission.requestWithPrompt()
        return 3
    }
    let controller = WindowController(backend: AXWindowBackend())
    var allCompleted = true
    for text in commands {
        print("> \(text)")
        do throws(CommandParseError) {
            switch try WindowCommandParser.parse(text) {
            case .window(let command):
                let result = await controller.perform(command)
                print(result.report)
                allCompleted = allCompleted && result.status == .completed
            case .list(let app):
                do throws(WindowError) {
                    let windows = try controller.listWindows(app)
                    if windows.isEmpty { print("  (no windows)") }
                    for w in windows {
                        print("  [\(w.id)] \(w.displayName) \(w.frame.compactDescription)\(w.isMinimized ? " (minimized)" : "")")
                    }
                } catch {
                    print("  error: \(error.userMessage)")
                    allCompleted = false
                }
            }
        } catch {
            print("  parse error: \(error.message)")
            allCompleted = false
        }
    }
    return allCompleted ? 0 : 1
}

exit(await run())
