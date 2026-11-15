import Foundation
import NaturalLanguage

/// A planned edit, ready to apply against exactly `change.baseVersion`.
public struct EditPlan: Sendable, Equatable {
    public let change: TextChange
    public let summary: String
    /// Text before and after (for previews and highlights).
    public let before: String
    public let after: String
    /// Changed span in the *result* text (for highlighting and `lastEditedRange`).
    public let changedRange: TextRange
    /// Substantial changes are shown for accept/discard before they are applied.
    public let requiresPreview: Bool
}

/// Several places match; the user must choose (never guessed, spec 02 §12).
public struct OccurrenceChoice: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case replace(new: String)
        case delete
        /// The utterance splits into old/new in more than one valid way.
        case split([String])
    }

    public let kind: Kind
    public let phrase: String
    public let prompt: String
    /// Spoken/visible options with surrounding context.
    public let options: [String]
    public let ranges: [TextRange]
    public let baseVersion: Int
}

public enum EditorDecision: Sendable, Equatable {
    case plan(EditPlan)
    case choose(OccurrenceChoice)
    case notFound(String)
    case nothingToDo(String)
}

/// Pure planning of deterministic edits on a snapshot (no I/O, fully unit-tested).
public enum TextEditor {
    /// A change is substantial (previewed) when it touches more than this many UTF-16 units
    /// *and* more than `substantialFraction` of the text, or removes most of it.
    public static let substantialUnits = 80
    public static let substantialFraction = 0.35

    public static func plan(_ op: EditOperation, on snap: TextSnapshot) -> EditorDecision {
        let text = snap.text as NSString
        switch op {
        case .append(let content):
            guard !content.isEmpty else { return .nothingToDo("There's nothing to add.") }
            var sep = separator(before: text.length, in: text, inserting: content)
            // "Also say I'll be late" after "I can meet at 4" starts a new sentence: end the
            // previous one. Only when it ends in a letter or digit and the addition is a sentence.
            if sep == " ", let prev = Unicode.Scalar(text.character(at: text.length - 1)), CharacterSet.alphanumerics.contains(prev),
               let first = content.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first), content.contains(" ") {
                sep = ". "
            }
            return .plan(make(snap, [Replacement(range: TextRange(location: text.length, length: 0), text: sep + content)],
                              summary: "Added “\(content)”"))

        case .prepend(let content):
            guard !content.isEmpty else { return .nothingToDo("There's nothing to add.") }
            let sep = text.length == 0 || content.hasSuffix(" ") ? "" : " "
            return .plan(make(snap, [Replacement(range: TextRange(location: 0, length: 0), text: content + sep)],
                              summary: "Started with “\(content)”"))

        case .insert(let content):
            guard !content.isEmpty else { return .nothingToDo("There's nothing to insert.") }
            let at = snap.selection ?? TextRange(location: text.length, length: 0)
            let before = separator(before: at.location, in: text, inserting: content)
            let after = at.end < text.length && isWordChar(text.character(at: at.end)) && !content.hasSuffix(" ") ? " " : ""
            return .plan(make(snap, [Replacement(range: at, text: before + content + after)], summary: "Inserted “\(content)”"))

        case .replace(let spoken, let occurrence):
            // "change four to four thirty" on "meet at 4": match the number as the text writes it.
            let candidates = spoken.map { c in
                TextEditor.occurrences(of: c.old, in: snap.text).isEmpty ? (SpokenNumbers.restyled(old: c.old, new: c.new, in: snap.text) ?? c) : c
            }
            let valid = candidates.filter { !occurrences(of: $0.old, in: snap.text).isEmpty && $0.old != $0.new }
            guard let first = candidates.first else { return .nothingToDo("Say what to change.") }
            if valid.isEmpty {
                if candidates.contains(where: { $0.old == $0.new }) { return .nothingToDo("That's already what it says.") }
                return .notFound("I couldn't find “\(first.old)” in the text.")
            }
            // "change go to the store to visit the shop": when every valid old text is a prefix
            // of the longest valid one, the longest is the user's meaning.
            if valid.count > 1, let longest = valid.max(by: { $0.old.count < $1.old.count }),
               valid.allSatisfy({ longest.old.lowercased().hasPrefix($0.old.lowercased()) })
            {
                let found = occurrences(of: longest.old, in: snap.text)
                return pick(found, occurrence, phrase: longest.old, snap: snap, kind: .replace(new: longest.new)) { ranges in
                    make(snap, ranges.map { Replacement(range: $0, text: longest.new) }, summary: "Changed “\(longest.old)” to “\(longest.new)”")
                }
            }
            if valid.count > 1 {
                let options = valid.map { "change “\($0.old)” to “\($0.new)”" }
                return .choose(OccurrenceChoice(kind: .split(valid.map(\.old)), phrase: first.old,
                                                prompt: "Did you mean " + options.joined(separator: ", or ") + "?",
                                                options: options, ranges: [], baseVersion: snap.version))
            }
            let c = valid[0]
            let found = occurrences(of: c.old, in: snap.text)
            return pick(found, occurrence, phrase: c.old, snap: snap, kind: .replace(new: c.new)) { ranges in
                make(snap, ranges.map { Replacement(range: $0, text: c.new) },
                     summary: "Changed “\(c.old)” to “\(c.new)”" + (ranges.count > 1 ? " (\(ranges.count) places)" : ""))
            }

        case .delete(let target):
            switch target {
            case .lastSentence, .firstSentence:
                let s = sentences(in: snap.text)
                guard let sentence = target == .lastSentence ? s.last : s.first else { return .nothingToDo("There's no sentence to remove.") }
                return .plan(make(snap, [Replacement(range: widenForDeletion(sentence, in: text), text: "")],
                                  summary: "Removed the \(target == .lastSentence ? "last" : "first") sentence", previewIfSubstantial: true))
            case .lastWord:
                guard let word = words(in: snap.text).last else { return .nothingToDo("There's no word to remove.") }
                return .plan(make(snap, [Replacement(range: widenForDeletion(word, in: text), text: "")],
                                  summary: "Removed “\(text.substring(with: word.ns))”", previewIfSubstantial: true))
            case .phrase(let phrase, let occurrence):
                let found = occurrences(of: phrase, in: snap.text)
                guard !found.isEmpty else { return .notFound("I couldn't find “\(phrase)” in the text.") }
                return pick(found, occurrence, phrase: phrase, snap: snap, kind: .delete) { ranges in
                    make(snap, ranges.map { Replacement(range: widenForDeletion($0, in: text), text: "") },
                         summary: "Removed “\(phrase)”" + (ranges.count > 1 ? " (\(ranges.count) places)" : ""), previewIfSubstantial: true)
                }
            }

        case .undo, .rewrite:
            return .nothingToDo("Handled by the editing session.")
        }
    }

    /// The plan for one chosen occurrence (after the user answered a choice).
    public static func plan(choice: OccurrenceChoice, picking indices: [Int], on snap: TextSnapshot) -> EditorDecision {
        let ranges = indices.compactMap { choice.ranges.indices.contains($0) ? choice.ranges[$0] : nil }
        guard !ranges.isEmpty else { return .nothingToDo("That isn't one of the options.") }
        let text = snap.text as NSString
        switch choice.kind {
        case .replace(let new):
            return .plan(make(snap, ranges.map { Replacement(range: $0, text: new) }, summary: "Changed “\(choice.phrase)” to “\(new)”"))
        case .delete:
            return .plan(make(snap, ranges.map { Replacement(range: widenForDeletion($0, in: text), text: "") },
                              summary: "Removed “\(choice.phrase)”", previewIfSubstantial: true))
        case .split:
            return .nothingToDo("Handled by the editing session.")
        }
    }

    // MARK: Occurrences

    private static func pick(
        _ found: [TextRange], _ occurrence: Occurrence, phrase: String, snap: TextSnapshot, kind: OccurrenceChoice.Kind,
        build: ([TextRange]) -> EditPlan
    ) -> EditorDecision {
        switch occurrence {
        case .all:
            return .plan(build(found))
        case .last:
            return .plan(build([found.last!]))
        case .ordinal(let n):
            guard found.indices.contains(n - 1) else {
                return .notFound("“\(phrase)” appears \(found.count) time\(found.count == 1 ? "" : "s"), so there's no number \(n).")
            }
            return .plan(build([found[n - 1]]))
        case .only:
            if found.count == 1 { return .plan(build(found)) }
            let options = found.enumerated().map { "\($0.offset + 1). …\(context(around: $0.element, in: snap.text))…" }
            let prompt = "“\(phrase)” appears \(found.count) times: " + options.joined(separator: "; ") + ". Which one, or all of them?"
            return .choose(OccurrenceChoice(kind: kind, phrase: phrase, prompt: prompt, options: options, ranges: found,
                                            baseVersion: snap.version))
        }
    }

    /// Case-insensitive matches on token boundaries. "3" does not match inside "3:30" or
    /// "13"; "Sam" does not match inside "Samantha".
    public static func occurrences(of phrase: String, in text: String) -> [TextRange] {
        let p = phrase.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return [] }
        let ns = text as NSString
        var result: [TextRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let r = ns.range(of: p, options: [.caseInsensitive], range: search)
            guard r.location != NSNotFound else { break }
            if isBoundary(r, in: ns, phrase: p as NSString) { result.append(TextRange(location: r.location, length: r.length)) }
            let next = r.location + max(r.length, 1)
            search = NSRange(location: next, length: ns.length - next)
        }
        return result
    }

    static func isBoundary(_ r: NSRange, in ns: NSString, phrase: NSString) -> Bool {
        let firstIsWord = isWordChar(phrase.character(at: 0))
        let lastIsWord = isWordChar(phrase.character(at: phrase.length - 1))
        if firstIsWord, r.location > 0 {
            let prev = ns.character(at: r.location - 1)
            if isWordChar(prev) { return false }
            // "3" after "12:" or "1." is part of a number/time.
            if isDigit(phrase.character(at: 0)), (prev == 0x3A || prev == 0x2E), r.location > 1, isDigit(ns.character(at: r.location - 2)) {
                return false
            }
        }
        if lastIsWord, r.location + r.length < ns.length {
            let next = ns.character(at: r.location + r.length)
            if isWordChar(next) { return false }
            if isDigit(phrase.character(at: phrase.length - 1)), (next == 0x3A || next == 0x2E),
               r.location + r.length + 1 < ns.length, isDigit(ns.character(at: r.location + r.length + 1))
            {
                return false
            }
        }
        return true
    }

    // MARK: Text structure

    public static func sentences(in text: String) -> [TextRange] { tokens(text, unit: .sentence) }
    public static func words(in text: String) -> [TextRange] { tokens(text, unit: .word) }

    private static func tokens(_ text: String, unit: NLTokenUnit) -> [TextRange] {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { r in
            let ns = NSRange(r, in: text)
            // Sentence tokens include trailing whitespace; trim it so deletions are exact.
            let sub = (text as NSString).substring(with: ns)
            let trimmed = sub.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let len = (trimmed as NSString).length
            return len == 0 ? nil : TextRange(location: ns.location, length: len)
        }
    }

    /// Removes one adjacent space so "a b c" minus "b" is "a c", not "a  c".
    static func widenForDeletion(_ r: TextRange, in ns: NSString) -> TextRange {
        let before = r.location > 0 ? ns.character(at: r.location - 1) : nil
        let after = r.end < ns.length ? ns.character(at: r.end) : nil
        if let b = before, isSpace(b) { return TextRange(location: r.location - 1, length: r.length + 1) }
        if let a = after, isSpace(a) { return TextRange(location: r.location, length: r.length + 1) }
        return r
    }

    /// A space before inserted content when it would otherwise join the previous word.
    static func separator(before location: Int, in ns: NSString, inserting content: String) -> String {
        guard location > 0, let first = content.utf16.first else { return "" }
        let prev = ns.character(at: location - 1)
        if isSpace(prev) || isSpace(first) { return "" }
        if [0x2C, 0x2E, 0x3B, 0x3A, 0x21, 0x3F, 0x29].contains(first) { return "" }  // , . ; : ! ? )
        return " "
    }

    /// "…meet [tomorrow] at 3…": the occurrence is bracketed so identical contexts differ.
    static func context(around r: TextRange, in text: String) -> String {
        let ns = text as NSString
        let start = max(0, r.location - 18), end = min(ns.length, r.end + 18)
        let left = ns.substring(with: NSRange(location: start, length: r.location - start))
        let right = ns.substring(with: NSRange(location: r.end, length: end - r.end))
        return (left + "[" + ns.substring(with: r.ns) + "]" + right).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isWordChar(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return true }  // surrogate halves: part of a word
        return CharacterSet.alphanumerics.contains(scalar) || c == 0x27  // apostrophe joins words
    }

    static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isSpace(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    // MARK: Building

    /// - Parameter previewIfSubstantial: deletions and rewrites are previewed when large;
    ///   explicit replacements and insertions are targeted edits (exact text the user said),
    ///   applied directly with undo (PRD D-011).
    static func make(_ snap: TextSnapshot, _ replacements: [Replacement], summary: String, previewIfSubstantial: Bool = false) -> EditPlan {
        let after = TextChange.apply(replacements, to: snap.text)
        let sorted = replacements.sorted { $0.range.location < $1.range.location }
        // Changed span in result coordinates: from the first replacement to the end of the last.
        var shift = 0
        var firstStart = 0, lastEnd = 0
        for (i, r) in sorted.enumerated() {
            let newLen = (r.text as NSString).length
            let start = r.range.location + shift
            if i == 0 { firstStart = start }
            lastEnd = start + newLen
            shift += newLen - r.range.length
        }
        let changed = sorted.reduce(0) { $0 + $1.range.length + ($1.text as NSString).length }
        let total = max((snap.text as NSString).length, 1)
        let removed = sorted.reduce(0) { $0 + $1.range.length }
        let substantial = previewIfSubstantial
            && ((changed > substantialUnits && Double(changed) / Double(total) > substantialFraction)
                || (total > 1 && Double(removed) / Double(total) > 0.5))
        let change = TextChange(document: snap.document, baseVersion: snap.version, baseHash: snap.contentHash,
                                replacements: replacements, expectedText: after,
                                caretAfter: TextRange(location: lastEnd, length: 0))
        return EditPlan(change: change, summary: summary, before: snap.text, after: after,
                        changedRange: TextRange(location: firstStart, length: max(0, lastEnd - firstStart)),
                        requiresPreview: substantial)
    }
}
