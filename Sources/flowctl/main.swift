import AppKit
import FlowAX
import FlowCore
import FlowMail
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
    let windowBackend = AXWindowBackend()
    let controller = WindowController(backend: windowBackend)
    // One navigator for the whole invocation, so "show numbers" then "choose 2" works.
    // Commands come from a terminal, so bring the target app forward first (Stage Manager hides
    // windows of apps outside the current stage from Accessibility).
    var navConfig = UINavigator.Configuration()
    navConfig.bringTargetToFront = true
    let navigator = UINavigator(backend: AXUIBackend(frontmost: { windowBackend.frontmostApp() }), configuration: navConfig)
    let mail = MailController(backend: JXAMailBackend(), verifier: AXMailDisplayVerifier())
    var allCompleted = true
    for text in commands {
        print("> \(text)")
        if text.lowercased().hasPrefix("mail ") || text.lowercased().hasPrefix("email ") {
            do throws(MailParseError) {
                let result = await mail.perform(try MailCommandParser.parse(text))
                print(result.report)
                if let content = result.content { print("  --- body ---\n\(content.body)\n  --- end ---") }
                allCompleted = allCompleted && (result.status == .completed || result.status == .needsClarification)
            } catch {
                print("  parse error: \(error.message)")
                allCompleted = false
            }
            continue
        }
        let windowVerbs: Set<String> = ["activate", "open", "switch", "launch", "move", "resize", "tile", "minimize",
                                        "minimise", "restore", "unminimize", "undo", "list"]
        let verb = text.split(separator: " ").first.map { $0.lowercased() } ?? ""
        let windowParse = Result { () throws(CommandParseError) in try WindowCommandParser.parse(text) }
        if case .failure = windowParse, !(windowVerbs.contains(verb) && verb != "activate") {
            // Not a window command: try UI navigation.
            do throws(NavParseError) {
                let command = try NavCommandParser.parse(text, isRunningApp: isRunningApp)
                let result = await navigator.perform(command)
                print(result.report)
                if let clarification = result.clarification { print("  numbers: \(clarification.prompt)") }
                allCompleted = allCompleted && (result.status == .completed || result.status == .needsClarification)
            } catch {
                print("  parse error: \(error.message)")
                allCompleted = false
            }
            continue
        }
        do throws(CommandParseError) {
            switch try windowParse.get() {
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

@MainActor
func isRunningApp(_ name: String) -> Bool {
    let key = name.lowercased()
    return NSWorkspace.shared.runningApplications.contains {
        $0.activationPolicy == .regular && ($0.localizedName?.lowercased() == key || $0.bundleIdentifier?.lowercased() == key)
    }
}

exit(await run())
