import Foundation

/// Produces a rewritten version of a text (e.g. Bonsai via LM Studio, later). FlowText never
/// applies its output directly: every rewrite is previewed and fact-checked first.
public protocol RewriteGenerating: Sendable {
    func rewrite(_ text: String, style: RewriteStyle) async -> String?
}

/// Factual slots that a rewrite must preserve (spec 02 §12: names, dates, times, numbers, URLs).
public enum FactCheck {
    static let patterns: [String] = [
        #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#,                                   // emails
        #"\bhttps?://\S+|\bwww\.\S+"#,                                          // URLs
        #"\b\d{1,2}(?::\d{2})?\s?(?:[ap]\.?m\.?)(?![a-z])"#,                    // times with am/pm
        #"\b\d{1,2}:\d{2}\b"#,                                                   // clock times
        #"\b\d{1,2}(?:st|nd|rd|th)\b"#,                                          // ordinals (dates)
        #"(?i)\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tonight|tomorrow|yesterday)\b"#,
        #"(?i)\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b"#,
        #"[$€£]\s?\d[\d,]*(?:\.\d+)?|\b\d[\d,]*(?:\.\d+)?\b"#,                     // money and numbers
    ]

    /// Facts in `text`, lowercased, plus capitalized words that are not sentence-initial (names).
    public static func facts(in text: String) -> Set<String> {
        var found = Set<String>()
        let ns = text as NSString
        // Patterns run in priority order; a matched span is masked so "3:30" is one fact,
        // not also "3" and "30".
        var taken = IndexSet()
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let span = IndexSet(integersIn: m.range.location..<(m.range.location + m.range.length))
                guard taken.intersection(span).isEmpty else { continue }
                taken.formUnion(span)
                found.insert(ns.substring(with: m.range).lowercased().replacingOccurrences(of: " ", with: ""))
            }
        }
        // Proper names: capitalized words that do not start a sentence.
        let nameRe = try! NSRegularExpression(pattern: #"(?<![.!?]\s)(?<!^)\b[A-Z][a-z]{1,}\b"#)
        for m in nameRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let w = ns.substring(with: m.range)
            if !["I", "I'm", "I'll"].contains(w) { found.insert(w.lowercased()) }
        }
        return found
    }

    public static func compare(original: String, proposed: String) -> (missing: [String], added: [String]) {
        let before = facts(in: original), after = facts(in: proposed)
        return (before.subtracting(after).sorted(), after.subtracting(before).sorted())
    }
}
