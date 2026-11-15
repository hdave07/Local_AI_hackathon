import FlowCore
import Foundation

/// Which occurrence of a phrase the user meant.
public enum Occurrence: Sendable, Equatable {
    case only
    case ordinal(Int)  // 1-based
    case last
    case all
}

public enum DeleteTarget: Sendable, Equatable {
    case lastSentence
    case firstSentence
    case lastWord
    case phrase(String, Occurrence)
}

public enum RewriteStyle: String, Sendable, Equatable {
    case shorter, formal, friendlier, clearer, rephrase
}

/// A deterministic editing request. Operands are the user's exact words.
public enum EditOperation: Sendable, Equatable {
    /// Append at the end: "add that I'll be late", "also say I'm available Friday".
    case append(String)
    /// Insert at the beginning: "start with Hi Sarah".
    case prepend(String)
    /// Literal text at the caret (dictation), or at the end without a caret.
    case insert(String)
    /// "change 3:30 to 4", "replace tomorrow with Wednesday". `candidates` lists every
    /// way to split the utterance into old/new when "to"/"with" also appears inside them;
    /// the editor keeps the splits whose old text exists.
    case replace(candidates: [(old: String, new: String)], Occurrence)
    case delete(DeleteTarget)
    case undo
    /// Substantial rewrite: always previewed, never applied directly.
    case rewrite(RewriteStyle)

    public static func == (a: EditOperation, b: EditOperation) -> Bool {
        switch (a, b) {
        case (.append(let x), .append(let y)), (.prepend(let x), .prepend(let y)), (.insert(let x), .insert(let y)): x == y
        case (.replace(let c1, let o1), .replace(let c2, let o2)):
            o1 == o2 && c1.count == c2.count && zip(c1, c2).allSatisfy { $0.old == $1.old && $0.new == $1.new }
        case (.delete(let x), .delete(let y)): x == y
        case (.undo, .undo): true
        case (.rewrite(let x), .rewrite(let y)): x == y
        default: false
        }
    }
}

/// Result of reading one utterance in command mode.
public enum ParsedUtterance: Sendable, Equatable {
    case control(ControlCommand)
    case startDictation(initial: String?)
    case edit(EditOperation)
    /// An editing-shaped request FlowText must never perform.
    case refused(String)
    /// Not an editing request: the caller routes it elsewhere (planner, router).
    case notAnEdit
}

/// Deterministic parser for editing commands (spec 02 §12). No model involved.
public enum EditCommandParser {
    public static func parse(_ raw: String) -> ParsedUtterance {
        if let control = DeterministicRouter.route(raw)?.control { return .control(control) }
        let s = clean(raw)
        guard !s.isEmpty else { return .notAnEdit }
        let lower = s.lowercased()

        // Dictation.
        if let m = match(#"^(?:start|begin) (?:dictation|dictating)$|^take dictation$|^dictation mode$"#, s) , m.isEmpty {
            return .startDictation(initial: nil)
        }
        if let m = match(#"^(?:dictate|type)[:,]?\s+(.+)$"#, s) {
            return .edit(.insert(m[0]))
        }

        // Never: deleting or sending the document itself.
        if match(#"^(?:delete|remove|discard|trash|erase|clear)\s+(?:the|this|my|that)?\s*(?:whole\s+|entire\s+)?(?:draft|email|e-mail|message|note|document|text|everything|all of it|reply)$"#, lower) != nil {
            return .refused("I can edit text, but I won't delete the whole draft or message.")
        }

        // Undo.
        if match(#"^(?:undo|scratch that|take that back|revert)(?:\s+(?:that|it|this|the last|my last))?(?:\s+(?:change|edit|one))?$"#, lower) != nil {
            return .edit(.undo)
        }

        // Delete parts.
        if match(#"^(?:remove|delete|drop|cut|take out)\s+(?:the\s+)?last\s+sentence$"#, lower) != nil { return .edit(.delete(.lastSentence)) }
        if match(#"^(?:remove|delete|drop|cut|take out)\s+(?:the\s+)?first\s+sentence$"#, lower) != nil { return .edit(.delete(.firstSentence)) }
        if match(#"^(?:remove|delete|drop|cut|take out)\s+(?:the\s+)?last\s+word$"#, lower) != nil { return .edit(.delete(.lastWord)) }
        if match(#"^(?:remove|delete|drop|cut|take out)\s+(?:that|it|this|those|these)$"#, lower) != nil {
            return .refused("Which words should I remove? Say “remove” and the words, or “undo that”.")
        }
        if let m = match(#"^(?:remove|delete|drop|cut|take out)\s+(?:the\s+(?:word|words|phrase)\s+)?(.+)$"#, s) {
            let (phrase, occurrence) = ordinal(m[0])
            return .edit(.delete(.phrase(unquote(phrase), occurrence)))
        }

        // Append / prepend (content kept verbatim, including its own punctuation).
        // Content is matched on the raw words (wake word removed) so its punctuation survives.
        let verbatim = stripWake(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if let m = match(#"^(?:add|append|also say|also add|then say|and say|add on)\s+(?:that\s+)?(.+?)(?:\s+(?:at the end|to the end))?$"#, verbatim) {
            return .edit(.append(unquote(m[0])))
        }
        if let m = match(#"^(?:start|begin) (?:it )?with\s+(.+)$"#, verbatim) {
            return .edit(.prepend(unquote(m[0])))
        }

        // Replace: every split point of "to"/"with"/"into" is a candidate; the text decides.
        if let m = match(#"^(?:change|replace|swap|correct)\s+(.+)$"#, s) {
            let candidates = splits(m[0])
            if !candidates.isEmpty {
                let first = ordinal(candidates[0].old)
                let occurrence = first.1
                let cands = candidates.map { c in (old: unquote(ordinal(c.old).0), new: unquote(stripSpokenPeriod(c.new))) }
                return .edit(.replace(candidates: cands, occurrence))
            }
        }

        // Rewrites (previewed).
        let rewrites: [(String, RewriteStyle)] = [
            (#"^(?:make it|make this|make that)\s+(?:a bit |a little )?(?:shorter|more concise|briefer)$|^shorten (?:it|this)$"#, .shorter),
            (#"^(?:make it|make this|make that)\s+(?:more |sound more )?(?:formal|professional)$|^(?:sound|be) more (?:formal|professional)$"#, .formal),
            (#"^(?:make it|make this|make that)\s+(?:more |sound )?(?:friendlier|friendly|warmer|nicer|more casual)$"#, .friendlier),
            (#"^(?:make it|make this|make that)\s+(?:clearer|simpler)$"#, .clearer),
            (#"^(?:rephrase|rewrite|reword)(?:\s+(?:it|this|that))?$"#, .rephrase),
        ]
        for (pattern, style) in rewrites where match(pattern, lower) != nil { return .edit(.rewrite(style)) }

        return .notAnEdit
    }

    // MARK: Helpers

    /// Removes the wake word and ASR's final period on the *command*; content keeps its own.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'")
        s = stripWake(s)
        if s.hasSuffix("."), !s.hasSuffix("..") { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func stripWake(_ s: String) -> String {
        guard let r = s.range(of: #"^(?:hey\s+)?flow[,.!]?\s+"#, options: [.regularExpression, .caseInsensitive]) else { return s }
        return String(s[r.upperBound...])
    }

    /// "4." spoken at the end of "change 3:30 to 4." is not part of the new text.
    static func stripSpokenPeriod(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("."), !t.hasSuffix(".."), !t.lowercased().hasSuffix("a.m."), !t.lowercased().hasSuffix("p.m.") { t.removeLast() }
        return t
    }

    /// Splits "A to B" at every " to "/" with "/" into " (quoted spans are never split).
    static func splits(_ body: String) -> [(old: String, new: String)] {
        if let m = match(#"^["“](.+?)["”]\s+(?:to|with|into|for)\s+["“]?(.+?)["”]?$"#, body) { return [(m[0], m[1])] }
        let ns = body as NSString
        let re = try! NSRegularExpression(pattern: #"\s+(?:to|with|into)\s+"#, options: [.caseInsensitive])
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let old = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            let new = ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: .whitespaces)
            return old.isEmpty || new.isEmpty ? nil : (old, new)
        }
    }

    /// "the second tomorrow" → ("tomorrow", .ordinal(2)); "all the tomorrows"/"every tomorrow" → .all.
    static func ordinal(_ phrase: String) -> (String, Occurrence) {
        let words: [(String, Occurrence)] = [
            ("first", .ordinal(1)), ("second", .ordinal(2)), ("third", .ordinal(3)), ("fourth", .ordinal(4)), ("last", .last),
        ]
        for (w, o) in words {
            if let m = match(#"^the\s+"# + w + #"\s+(.+)$"#, phrase) { return (m[0], o) }
        }
        if let m = match(#"^(?:every|each|all(?: of)?(?: the)?)\s+(.+)$"#, phrase) { return (m[0], .all) }
        return (phrase, .only)
    }

    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] where t.count >= 2 && t.hasPrefix(open) && t.hasSuffix(close) {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    /// Anchored-by-pattern, case-insensitive regex; returns capture groups.
    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<max(1, m.numberOfRanges)).compactMap { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }
}
