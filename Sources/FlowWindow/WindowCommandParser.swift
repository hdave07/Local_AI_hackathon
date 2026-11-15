import FlowCore
import Foundation

/// Deterministic typed-command interface for testing window control without speech
/// or the model. Shared by the SwiftUI test panel, `flowctl`, and integration tests.
///
/// Grammar (case-insensitive):
///   activate|open|switch <app>
///   move <app|active> ["title"] <left_half|right_half|maximize|center>
///   resize <app|active> ["title"] <wider|narrower|taller|shorter|larger|smaller>
///   tile <app> <app>          (also "tile mail and calendar")
///   minimize <app|active> ["title"]
///   restore <app|active> ["title"]
///   undo
///   list <app>
public enum TypedCommand: Sendable, Equatable {
    case window(WindowCommand)
    case list(KnownApp)
}

public struct CommandParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}

public enum WindowCommandParser {
    public static let usage = """
        activate <app> · move <app|active> ["title"] <left_half|right_half|maximize|center> · \
        resize <app|active> <wider|narrower|taller|shorter|larger|smaller> · tile <app> <app> · \
        minimize <app|active> · restore <app|active> · close <app|active> · undo · list <app>   (apps: mail, calendar, notes, finder, safari)
        """

    public static func parse(_ input: String) throws(CommandParseError) -> TypedCommand {
        var (words, title) = try tokenize(input)
        guard let verb = words.first else { throw CommandParseError(message: "Type a command. \(usage)") }
        words.removeFirst()

        switch verb {
        case "undo":
            try expectEmpty(words, after: verb)
            return .window(.undo)

        case "activate", "open", "switch", "launch":
            if words.first == "to" { words.removeFirst() }
            guard words.count == 1 else { throw CommandParseError(message: "Usage: activate <app>") }
            return .window(.activate(try app(words[0])))

        case "list":
            guard words.count == 1 else { throw CommandParseError(message: "Usage: list <app>") }
            return .list(try app(words[0]))

        case "tile":
            let names = words.filter { $0 != "and" }
            guard names.count == 2 else { throw CommandParseError(message: "Usage: tile <app> <app>") }
            return .window(.tile(left: try app(names[0]), right: try app(names[1])))

        case "move":
            guard words.count == 2 else { throw CommandParseError(message: "Usage: move <app|active> [\"title\"] <position>") }
            guard let position = WindowPosition.parse(words[1]) else {
                throw CommandParseError(message: "Unknown position “\(words[1])”. Use left_half, right_half, maximize or center.")
            }
            return .window(.move(try selector(words[0], title), position))

        case "resize":
            guard words.count == 2 else { throw CommandParseError(message: "Usage: resize <app|active> [\"title\"] <change>") }
            guard let change = ResizeChange.parse(words[1]) else {
                throw CommandParseError(message: "Unknown size change “\(words[1])”.")
            }
            return .window(.resize(try selector(words[0], title), change))

        case "minimize", "minimise":
            guard words.count == 1 else { throw CommandParseError(message: "Usage: minimize <app|active>") }
            return .window(.minimize(try selector(words[0], title)))

        case "restore", "unminimize":
            guard words.count == 1 else { throw CommandParseError(message: "Usage: restore <app|active>") }
            return .window(.restore(try selector(words[0], title)))

        case "close":
            guard words.count == 1 else { throw CommandParseError(message: "Usage: close <app|active>") }
            return .window(.close(try selector(words[0], title)))

        default:
            throw CommandParseError(message: "Unknown command “\(verb)”. \(usage)")
        }
    }

    /// Splits on whitespace, extracting at most one double-quoted window title.
    static func tokenize(_ input: String) throws(CommandParseError) -> ([String], String?) {
        let parts = input.components(separatedBy: "\"")
        guard parts.count == 1 || parts.count == 3 else {
            throw CommandParseError(message: "Put a window title in one pair of double quotes.")
        }
        let title = parts.count == 3 ? parts[1] : nil
        let rest = parts.count == 3 ? parts[0] + " " + parts[2] : parts[0]
        let words = rest.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return (words, title)
    }

    private static func app(_ word: String) throws(CommandParseError) -> KnownApp {
        guard let app = KnownApp.parse(word) else {
            throw CommandParseError(message: "Unsupported app “\(word)”. Use mail, calendar, notes, finder or safari.")
        }
        return app
    }

    private static func selector(_ word: String, _ title: String?) throws(CommandParseError) -> WindowSelector {
        if word == "active" || word == "this" || word == "current" { return WindowSelector(.active, title: title) }
        return .app(try app(word), title: title)
    }

    private static func expectEmpty(_ words: [String], after verb: String) throws(CommandParseError) {
        guard words.isEmpty else { throw CommandParseError(message: "“\(verb)” takes no arguments.") }
    }
}
