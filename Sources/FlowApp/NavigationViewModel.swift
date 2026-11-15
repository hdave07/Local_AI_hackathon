import AppKit
import FlowAX
import FlowWindow
import Foundation
import Observation

/// Typed test interface for FlowAX inside the app. Commands go through the deterministic
/// NavCommandParser → UINavigator path (same as `flowctl` and the live tests). Classifier
/// output is not connected here.
@MainActor
@Observable
final class NavigationViewModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let input: String
        let status: NavigationStatus?
        let text: String
    }

    var command = ""
    private(set) var isRunning = false
    private(set) var log: [LogEntry] = []
    private(set) var numbers: [NumberedTarget] = []
    private(set) var prompt: String?

    private let navigator: UINavigator

    init(navigator: UINavigator) {
        self.navigator = navigator
    }

    func submit() {
        let text = command
        Task { await run(text) }
    }

    func run(_ text: String) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let entry: LogEntry
        do throws(NavParseError) {
            let command = try NavCommandParser.parse(text, isRunningApp: Self.isRunningApp)
            let result = await navigator.perform(command)
            entry = LogEntry(input: text, status: result.status, text: result.report)
        } catch {
            entry = LogEntry(input: text, status: nil, text: error.message)
        }
        numbers = navigator.currentNumbers
        prompt = numbers.isEmpty ? nil : "Type “choose <n>” or click a number."
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast() }
    }

    static func isRunningApp(_ name: String) -> Bool {
        let key = name.lowercased()
        return NSWorkspace.shared.runningApplications.contains {
            $0.activationPolicy == .regular && ($0.localizedName?.lowercased() == key || $0.bundleIdentifier?.lowercased() == key)
        }
    }
}
