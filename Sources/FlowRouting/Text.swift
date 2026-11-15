import FlowCore
import Foundation

/// Light cleanup of a finalized ASR utterance before deterministic matching.
///
/// Casing and inner punctuation are kept, so captured message content, times and
/// names are copied exactly as recognized. Only wrappers are removed: the wake word,
/// politeness ("can you … please"), fillers ("uh", "um") and final punctuation.
enum Cleaner {
    private static let wake = Rx(#"(?:hey\s+)?flow[,.!]?\s+(.+)"#)
    private static let polite = Rx(#"(?:(?:ok|okay|hey)[,]?\s+)?(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?|please\s+)(.+?)"#)
    private static let politeTail = Rx(#"(.+?)[,]?\s+please"#)

    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "’", with: "'")
        s = normalizeTimes(s)
        s = collapse(s)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?").union(.whitespaces))
        if let m = wake.match(s), let rest = m[0] { s = rest }
        // Fillers anywhere ("uh", "um", "erm"), with an optional trailing comma.
        s = s.replacingOccurrences(of: #"\b(?:uh|um|erm|uhm)\b,?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = collapse(s)
        if let m = polite.match(s), let rest = m[0] { s = rest }
        if let m = politeTail.match(s), let rest = m[0] { s = rest }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,").union(.whitespaces))
    }

    /// ASR writes times as "2 p.m.", "2.30 p.m."; Flow uses "2 pm", "2:30 pm". Only the
    /// unambiguous am/pm forms are rewritten; a bare "2.30" or "230" is left for a question.
    static func normalizeTimes(_ s: String) -> String {
        var t = s.replacingOccurrences(
            of: #"\b([ap])\.\s?m\.?(?=\s|$|[,;!?])"#, with: "$1m", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(
            of: #"\b(1[0-2]|0?[1-9])\.([0-5][0-9])\s?([ap]m)\b"#, with: "$1:$2 $3", options: [.regularExpression, .caseInsensitive])
        return t
    }

    /// "?" or "!" ending the raw utterance: meaningful in dictated content, unlike ASR's final ".".
    static func terminalMark(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("?") { return "?" }
        if t.hasSuffix("!") { return "!" }
        return ""
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Anchored, case-insensitive regular expression returning its capture groups.
struct Rx: @unchecked Sendable {
    private let re: NSRegularExpression

    init(_ pattern: String) {
        // Patterns are compile-time constants; a bad one is a programming error.
        re = try! NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: [.caseInsensitive])
    }

    /// Capture groups (nil when a group did not participate), or nil if no full match.
    func match(_ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<max(1, m.numberOfRanges)).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}

/// Word-level helpers for grounding checks.
enum Words {
    static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "fifteen": "15", "twenty": "20",
        "thirty": "30", "forty": "40", "fortyfive": "45", "noon": "12", "midnight": "12",
    ]

    /// Words that carry no slot information.
    static let stopwords: Set<String> = [
        "a", "an", "the", "to", "at", "on", "in", "of", "for", "my", "me", "about", "from", "and", "is", "it", "that",
        "this", "i", "you", "with", "s", "o", "clock", "oclock", "please", "be", "are", "was", "will", "so", "just",
    ]

    /// Lowercased alphanumeric tokens with number words mapped to digits ("3:45" → 3, 45).
    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { numberWords[$0] ?? ordinal($0) }
    }

    /// "12th" → "12", "1st" → "1".
    static func ordinal(_ t: String) -> String {
        for suffix in ["st", "nd", "rd", "th"] where t.hasSuffix(suffix) {
            let head = t.dropLast(2)
            if !head.isEmpty, head.allSatisfy(\.isNumber) { return String(head) }
        }
        return t
    }

    static func contentTokens(_ s: String) -> [String] {
        tokens(s).filter { !stopwords.contains($0) }
    }
}

extension KnownApp {
    /// App named by a phrase such as "the mail app", "notes window", "email". Nil otherwise.
    static func fromPhrase(_ raw: String) -> KnownApp? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        for prefix in ["the ", "my "] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        for suffix in [" window", " app", " application"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        if s == "e-mail" { s = "email" }
        // Frequent ASR homophone for "mail" in command positions ("the male window").
        // Applied to app names only, never to dictated content.
        if s == "male" { s = "mail" }
        return KnownApp.parse(s)
    }

    /// Words that ground a reference to this app in an utterance.
    var groundingWords: Set<String> {
        switch self {
        case .mail: ["mail", "email", "inbox", "male"]
        case .calendar: ["calendar", "ical", "schedule"]
        case .notes: ["notes", "note"]
        case .finder: ["finder", "files"]
        case .safari: ["safari", "browser"]
        }
    }
}
