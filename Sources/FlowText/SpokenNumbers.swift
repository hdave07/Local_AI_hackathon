import Foundation

/// Spoken numbers and clock times written two ways: speech recognition may type "4" or "4:30"
/// while the user says "four" or "four thirty". Used only as a fallback when the user's words
/// aren't found literally; the replacement then follows the style already in the text.
public enum SpokenNumbers {
    static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]
    static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]
    static let names: [Int: String] = Dictionary(uniqueKeysWithValues: units.map { ($1, $0) })

    /// "four" → 4, "twenty five" → 25, "4" → 4.
    static func value(_ words: [String]) -> Int? {
        if words.count == 1, let n = Int(words[0]) { return n }
        if words.count == 1 { return units[words[0]] ?? tens[words[0]] }
        if words.count == 2, let t = tens[words[0]], let u = units[words[1]], u < 10 { return t + u }
        return nil
    }

    /// The same number or time written as digits: "four" → "4", "four thirty" → "4:30",
    /// "half past four" → "4:30", "quarter past four" → "4:15", "four o'clock" → "4". Nil if not a number.
    public static func digits(_ phrase: String) -> String? {
        let w = phrase.lowercased().replacingOccurrences(of: "o'clock", with: "").replacingOccurrences(of: "oclock", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard !w.isEmpty else { return nil }
        if w.count >= 3, w[1] == "past" || w[1] == "after", let h = value(Array(w[2...])) {
            switch w[0] { case "half": return "\(h):30"; case "quarter": return "\(h):15"; default: break }
        }
        if let n = value(w) { return String(n) }
        // "four thirty", "four oh five", "four forty five"
        if let h = value([w[0]]), h >= 1, h <= 12 {
            let rest = Array(w.dropFirst())
            if rest.first == "oh", rest.count == 2, let m = value([rest[1]]), m < 10 { return "\(h):0\(m)" }
            if let m = value(rest), m >= 10, m < 60 { return "\(h):\(m)" }
        }
        return nil
    }

    /// The same number written as words ("4" → "four", "4:30" → "four thirty"), for text that uses words.
    public static func words(_ phrase: String) -> String? {
        let p = phrase.trimmingCharacters(in: .whitespaces)
        let parts = p.split(separator: ":").map(String.init)
        guard let h = Int(parts[0]), let hw = name(h) else { return nil }
        if parts.count == 1 { return hw }
        guard parts.count == 2, let m = Int(parts[1]), m < 60 else { return nil }
        if m == 0 { return hw }
        if m < 10 { return names[m].map { "\(hw) oh \($0)" } }
        return name(m).map { "\(hw) \($0)" }
    }

    static func name(_ n: Int) -> String? {
        if let u = names[n] { return u }
        let t = n / 10 * 10, u = n % 10
        guard let tw = tens.first(where: { $0.value == t })?.key else { return nil }
        return u == 0 ? tw : names[u].map { "\(tw) \($0)" }
    }

    /// When `old` isn't in `text`, the same edit in the text's own number style, if that is found.
    static func restyled(old: String, new: String, in text: String) -> (old: String, new: String)? {
        if let d = digits(old), d != old, !TextEditor.occurrences(of: d, in: text).isEmpty {
            return (d, digits(new) ?? new)
        }
        if let w = words(old), w != old.lowercased(), !TextEditor.occurrences(of: w, in: text).isEmpty {
            return (w, words(new) ?? new)
        }
        return nil
    }
}
