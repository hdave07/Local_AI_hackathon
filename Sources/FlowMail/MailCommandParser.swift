import Foundation

public struct MailParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}

/// Deterministic typed-command interface for Mail (test harness; not model output).
///
/// Grammar (case-insensitive; a leading "mail"/"email" is optional):
///   find|search|show <criteria>        e.g. "find mail from Sarah", "find Sarah's email about meeting"
///   open <criteria>                    e.g. "open email with subject budget in mailbox FlowTest"
///   read <criteria>                    e.g. "read mail from Okafor"
///   read it | read current | read this message
///   choose <n> | pick <n> | <n>
///   status | allow access
/// Criteria: from <sender> · about <words> · with subject <text> · in mailbox <name>
/// Use double quotes for exact phrases: subject "Lunch on Friday".
public enum MailCommandParser {
    public static let usage = """
        find|open|read [mail] from <sender> · about <words> · with subject <text> · in mailbox <name> · \
        choose <n> · read it · status · allow access
        """

    static let fillers: Set<String> = ["mail", "email", "emails", "mails", "message", "messages", "the", "my", "an", "a", "me", "for", "any", "all"]
    static let keywords: Set<String> = ["from", "about", "subject", "in"]

    public static func parse(_ input: String) throws(MailParseError) -> MailCommand {
        var tokens = try tokenize(input)
        guard !tokens.isEmpty else { throw MailParseError(message: "Type a Mail command. \(usage)") }
        if ["mail", "email"].contains(tokens[0].lowercased()), tokens.count > 1 { tokens.removeFirst() }
        let verb = tokens.removeFirst().lowercased()
        let rest = tokens.map { $0.lowercased() }

        switch verb {
        case "status": return .status(requestPermission: false)
        case "allow", "permission", "authorize": return .status(requestPermission: true)
        case "choose", "pick", "number":
            guard tokens.count == 1, let n = Int(tokens[0]), n > 0 else { throw MailParseError(message: "Usage: choose <number>") }
            return .choose(n)
        case "find", "search", "show", "look", "list":
            if verb == "look", tokens.first?.lowercased() == "for" { tokens.removeFirst() }
            return .find(try query(tokens))
        case "open":
            return .open(try query(tokens))
        case "read":
            let words = Set(rest)
            if rest.isEmpty || words.isSubset(of: ["it", "this", "that", "current", "message", "email", "mail", "the", "one"]) {
                return .readActive
            }
            return .read(try query(tokens))
        default:
            if tokens.isEmpty, let n = Int(verb), n > 0 { return .choose(n) }
            throw MailParseError(message: "Unknown Mail command “\(verb)”. \(usage)")
        }
    }

    /// Parses criteria: possessive sender ("Sarah's email"), from/about/subject/in mailbox.
    static func query(_ input: [String]) throws(MailParseError) -> MailQuery {
        var tokens = input
        var query = MailQuery()
        // Leading fillers and a possessive sender: "Sarah's email about …"
        while let first = tokens.first, fillers.contains(first.lowercased()) { tokens.removeFirst() }
        if let first = tokens.first, first.lowercased().hasSuffix("'s") || first.hasSuffix("’s"),
            tokens.count >= 2, fillers.contains(tokens[1].lowercased())
        {
            query.sender = String(first.dropLast(2))
            tokens.removeFirst(2)
        }

        var field: String?
        var values: [String: [String]] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()
            if lower == "in", index + 1 < tokens.count, ["mailbox", "folder"].contains(tokens[index + 1].lowercased()) {
                field = "mailbox"
                index += 2
                continue
            }
            if lower == "with", index + 1 < tokens.count, tokens[index + 1].lowercased() == "subject" {
                field = "subject"
                index += 2
                continue
            }
            if ["from", "about", "subject", "titled", "called"].contains(lower) {
                field = ["titled", "called"].contains(lower) ? "subject" : lower
                index += 1
                continue
            }
            if let field {
                values[field, default: []].append(token)
            } else if !fillers.contains(lower) {
                values["about", default: []].append(token)
            }
            index += 1
        }
        if let from = values["from"] { query.sender = from.joined(separator: " ") }
        if let subject = values["subject"] { query.subject = subject.joined(separator: " ") }
        if let mailbox = values["mailbox"] { query.mailbox = mailbox.joined(separator: " ") }
        if let about = values["about"] { query.terms = about.filter { !fillers.contains($0.lowercased()) } }
        if query.isEmpty { throw MailParseError(message: "Say who it's from, its subject, or what it's about. \(usage)") }
        return query
    }

    /// Whitespace tokens; a double-quoted phrase stays one token.
    static func tokenize(_ input: String) throws(MailParseError) -> [String] {
        let normalized = input.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        let parts = normalized.components(separatedBy: "\"")
        guard parts.count % 2 == 1 else { throw MailParseError(message: "Close the quotation marks.") }
        var tokens: [String] = []
        for (i, part) in parts.enumerated() {
            if i % 2 == 1 {
                let phrase = part.trimmingCharacters(in: .whitespaces)
                if !phrase.isEmpty { tokens.append(phrase) }
            } else {
                tokens += part.split(whereSeparator: \.isWhitespace).map(String.init)
            }
        }
        return tokens
    }
}
