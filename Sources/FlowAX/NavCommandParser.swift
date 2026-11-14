import FlowCore
import Foundation

public struct NavParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}

/// Deterministic typed-command interface for UI navigation (test harness; not model output).
///
/// Grammar (case-insensitive; optional app suffix `in <running app>` or `in app <name>`):
///   click|press|select <target>             e.g. "click the Save button", "press seven in Calculator"
///   focus <target>                          e.g. "focus the search field"
///   scroll up|down|top|bottom [<target>]    e.g. "scroll down", "scroll down results list"
///   show numbers [for <target>]  |  numbers
///   choose <n>  |  pick <n>  |  number <n>  |  <n>
///   hide numbers
///   inspect
public enum NavCommandParser {
    public static let usage = """
        click <target> · focus <target> · scroll up|down|top|bottom [<target>] · show numbers [for <target>] · \
        choose <n> · hide numbers · inspect   (append “in <app>” to target a running app)
        """

    /// - Parameter isRunningApp: whether a phrase names a running regular app; used to decide
    ///   whether a trailing "in X" is an app scope or part of the label ("Keep in Dock").
    public static func parse(_ input: String, isRunningApp: (String) -> Bool = { _ in false }) throws(NavParseError) -> NavCommand {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NavParseError(message: "Type a command. \(usage)") }
        let scope = extractScope(&text, isRunningApp: isRunningApp)
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let verb = words.removeFirst().lowercased()
        let rest = words.joined(separator: " ")
        let lowerRest = rest.lowercased()

        switch verb {
        case "click", "press", "select", "tap", "push", "activate":
            return .click(try reference(rest, verb), scope)
        case "focus":
            return .focus(try reference(rest.replacingOccurrences(of: "^(on|in)\\s+", with: "", options: .regularExpression), verb), scope)
        case "scroll":
            guard let first = words.first, let direction = ScrollDirection(rawValue: first.lowercased()) else {
                throw NavParseError(message: "Usage: scroll up|down|top|bottom [<target>]")
            }
            let target = words.dropFirst().joined(separator: " ")
            return .scroll(target.isEmpty ? nil : TargetReference.parse(target), direction, scope)
        case "show", "numbers":
            var r = verb == "show" ? lowerRest : "numbers " + lowerRest
            guard r.hasPrefix("numbers") else { throw NavParseError(message: "Usage: show numbers [for <target>]") }
            r = String(r.dropFirst("numbers".count)).trimmingCharacters(in: .whitespaces)
            if r.hasPrefix("for ") { r = String(r.dropFirst(4)) }
            return .showNumbers(r.isEmpty ? nil : TargetReference.parse(r), scope)
        case "hide":
            guard lowerRest == "numbers" else { throw NavParseError(message: "Usage: hide numbers") }
            return .hideNumbers
        case "choose", "pick", "number":
            guard words.count == 1, let n = Int(words[0]), n > 0 else { throw NavParseError(message: "Usage: choose <number>") }
            return .choose(n)
        case "inspect":
            return .inspect(scope)
        default:
            if words.isEmpty, let n = Int(verb), n > 0 { return .choose(n) }
            throw NavParseError(message: "Unknown command “\(verb)”. \(usage)")
        }
    }

    private static func reference(_ text: String, _ verb: String) throws(NavParseError) -> TargetReference {
        let ref = TargetReference.parse(text)
        guard !ref.words.isEmpty || ref.roleHint != nil else { throw NavParseError(message: "Usage: \(verb) <target>") }
        return ref
    }

    /// Removes a trailing " in app X" (always a scope) or " in X" (a scope only if X is a running app).
    static func extractScope(_ text: inout String, isRunningApp: (String) -> Bool) -> AppScope {
        let lower = text.lowercased()
        if let range = lower.range(of: " in app ", options: .backwards) {
            let name = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                text = String(text[..<range.lowerBound])
                return .named(name)
            }
        }
        if let range = lower.range(of: " in ", options: .backwards) {
            let name = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let head = String(text[..<range.lowerBound])
            if !name.isEmpty, head.split(separator: " ").count >= 2 || head.lowercased().hasPrefix("inspect"), isRunningApp(name) {
                text = head
                return .named(name)
            }
        }
        if lower.hasPrefix("inspect in ") {
            let name = String(text.dropFirst("inspect in ".count))
            text = "inspect"
            return .named(name)
        }
        return .frontmost
    }
}
