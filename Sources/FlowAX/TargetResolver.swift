import Foundation

/// Kinds a spoken role word restricts matching to ("the Reply *button*").
public enum RoleHint: String, Sendable, Equatable {
    case button, textField, checkbox, tab, link, row, menu, slider, scrollArea

    var kinds: Set<ElementKind> {
        switch self {
        case .button: [.button, .menuButton]
        case .textField: [.textInput]
        case .checkbox: [.checkbox]
        case .tab: [.tab, .radio]
        case .link: [.link]
        case .row: [.row, .cell]
        case .menu: [.menuButton]
        case .slider: [.slider]
        case .scrollArea: [.scrollArea]
        }
    }
}

public enum Ordinal: Sendable, Equatable {
    case index(Int)  // 1-based, reading order
    case last
}

/// A spoken-style reference to a control, parsed deterministically:
/// "the second Reply button" → words ["reply"], role .button, ordinal 2.
public struct TargetReference: Sendable, Equatable, CustomStringConvertible {
    public let raw: String
    public let words: [String]
    public let roleHint: RoleHint?
    public let ordinal: Ordinal?

    public init(raw: String, words: [String], roleHint: RoleHint?, ordinal: Ordinal?) {
        self.raw = raw
        self.words = words
        self.roleHint = roleHint
        self.ordinal = ordinal
    }

    public var description: String { raw }

    static let articles: Set<String> = ["the", "a", "an", "on", "to", "into", "at"]
    static let ordinals: [String: Ordinal] = [
        "first": .index(1), "1st": .index(1), "second": .index(2), "2nd": .index(2),
        "third": .index(3), "3rd": .index(3), "fourth": .index(4), "4th": .index(4),
        "fifth": .index(5), "5th": .index(5), "last": .last,
    ]
    /// Trailing role words, longest first.
    static let roleWords: [([String], RoleHint)] = [
        (["text", "field"], .textField), (["search", "field"], .textField), (["search", "box"], .textField), (["text", "box"], .textField),
        (["check", "box"], .checkbox), (["pop", "up"], .menu), (["drop", "down"], .menu),
        (["scroll", "area"], .scrollArea),
        (["button"], .button), (["field"], .textField), (["textbox"], .textField), (["box"], .textField),
        (["input"], .textField), (["checkbox"], .checkbox), (["toggle"], .checkbox), (["switch"], .checkbox),
        (["tab"], .tab), (["link"], .link), (["row"], .row), (["item"], .row), (["cell"], .row),
        (["menu"], .menu), (["popup"], .menu), (["dropdown"], .menu), (["slider"], .slider),
        (["list"], .scrollArea), (["sidebar"], .scrollArea), (["table"], .scrollArea),
    ]

    public static func parse(_ raw: String) -> TargetReference {
        var words = LabelText.words(raw)
        while let first = words.first, articles.contains(first) { words.removeFirst() }
        var ordinal: Ordinal?
        if let first = words.first, let o = ordinals[first] {
            ordinal = o
            words.removeFirst()
        }
        var hint: RoleHint?
        for (suffix, role) in roleWords where words.count >= suffix.count && Array(words.suffix(suffix.count)) == suffix {
            hint = role
            // "search field" / "search box": "search" describes the control, keep it as a query word.
            words.removeLast(suffix.first == "search" ? 1 : suffix.count)
            break
        }
        return TargetReference(raw: raw, words: words, roleHint: hint, ordinal: ordinal)
    }

    /// The reference including any role word, for labels that contain it ("Show Sidebar").
    var fullWords: [String] {
        var w = LabelText.words(raw)
        while let first = w.first, Self.articles.contains(first) { w.removeFirst() }
        if let first = w.first, Self.ordinals[first] != nil { w.removeFirst() }
        return w
    }
}

/// Outcome of resolving a reference against one snapshot.
public enum Resolution: Sendable, Equatable {
    case unique(UIElementInfo)
    /// Several equally good matches: ask, never guess (spec 02 §7.3, D-013).
    case ambiguous([UIElementInfo])
    /// Only weak (partial-text) matches: confirm before acting.
    case lowConfidence([UIElementInfo])
    case notFound
}

/// Deterministic matching of references to visible elements. No model, no scores
/// beyond fixed match tiers; ties are reported, not broken arbitrarily.
public enum TargetResolver {
    enum Tier: Int, Comparable {
        case contains = 1, allWords = 2, prefix = 3, exact = 4
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    /// Small, generic word equivalences for spoken input.
    static let synonyms: [String: [String]] = [
        "zero": ["0"], "one": ["1"], "two": ["2"], "three": ["3"], "four": ["4"], "five": ["5"],
        "six": ["6"], "seven": ["7"], "eight": ["8"], "nine": ["9"], "ten": ["10"],
        "plus": ["add"], "minus": ["subtract"], "times": ["multiply"], "divided": ["divide"],
        "equal": ["equals"], "ok": ["okay"], "okay": ["ok"], "x": ["close"], "dot": ["point"],
    ]

    public static func candidates(for intent: NavigationIntent, in snapshot: UISnapshot) -> [UIElementInfo] {
        snapshot.elements.filter { e in
            guard e.isVisible, !UIElementInfo.scrollBarParts.contains(e.subrole ?? "") else { return false }
            switch intent {
            case .click: return e.canPress || e.canSelect
            case .focus: return e.canFocus && (e.kind == .textInput || e.kind == .menuButton || e.kind == .slider)
            case .scroll: return e.isScrollable
            }
        }
    }

    public static func resolve(_ reference: TargetReference, intent: NavigationIntent, in snapshot: UISnapshot) -> Resolution {
        var pool = candidates(for: intent, in: snapshot)
        if let hint = reference.roleHint {
            let narrowed = pool.filter { hint.kinds.contains($0.kind) }
            // A role word that matches nothing may be part of the label ("Show Sidebar").
            if !narrowed.isEmpty { pool = narrowed }
        }

        var best = match(reference.words, in: pool)
        // A role word alone may itself be the label ("the sidebar" → scroll area labelled "Sidebar").
        if reference.words.isEmpty, reference.fullWords.count > 0 {
            best = match(reference.fullWords, in: pool)
        }
        if best.isEmpty, reference.fullWords != reference.words {
            best = match(reference.fullWords, in: candidates(for: intent, in: snapshot))
        }
        // A bare role reference ("the text field") matches by kind alone.
        if best.isEmpty, reference.words.isEmpty, reference.roleHint != nil {
            best = pool.map { ($0, Tier.exact) }
        }
        guard let top = best.map(\.1).max() else { return .notFound }

        var matches = removeContainers(best.filter { $0.1 == top }.map(\.0), in: snapshot)
        matches.sort(by: readingOrder)

        if let ordinal = reference.ordinal {
            switch ordinal {
            case .index(let n) where n >= 1 && n <= matches.count: return .unique(matches[n - 1])
            case .last where !matches.isEmpty: return .unique(matches[matches.count - 1])
            default: return .notFound
            }
        }
        if top == .contains { return .lowConfidence(matches) }
        return matches.count == 1 ? .unique(matches[0]) : .ambiguous(matches)
    }

    static func match(_ query: [String], in pool: [UIElementInfo]) -> [(UIElementInfo, Tier)] {
        guard !query.isEmpty else { return [] }
        let variants = expand(query)
        return pool.compactMap { element in
            let labelWords = LabelText.words(element.label)
            var tier = variants.compactMap { tierOf($0, labelWords) }.max()
            if let id = element.identifier, LabelText.words(id) == query { tier = max(tier ?? .prefix, .prefix) }
            return tier.map { (element, $0) }
        }
    }

    static func tierOf(_ q: [String], _ label: [String]) -> Tier? {
        guard !label.isEmpty else { return nil }
        if label == q { return .exact }
        if label.starts(with: q) { return .prefix }
        if Set(q).isSubset(of: Set(label)) { return .allWords }
        let joinedQ = q.joined(separator: " "), joinedL = label.joined(separator: " ")
        if joinedQ.count >= 3, joinedL.contains(joinedQ) { return .contains }
        return nil
    }

    /// Query variants with each word optionally replaced by a synonym.
    static func expand(_ query: [String]) -> [[String]] {
        var variants: [[String]] = [query]
        for (i, word) in query.enumerated() {
            for alt in synonyms[word] ?? [] {
                variants += variants.map { v in var c = v; c[i] = alt; return c }
            }
        }
        return Array(variants.prefix(16))
    }

    /// When a container and its own descendant both match, keep the descendant.
    static func removeContainers(_ matches: [UIElementInfo], in snapshot: UISnapshot) -> [UIElementInfo] {
        matches.filter { candidate in
            !matches.contains { other in other.id != candidate.id && snapshot.isAncestor(candidate.id, of: other.id) }
        }
    }

    static func readingOrder(_ a: UIElementInfo, _ b: UIElementInfo) -> Bool {
        if abs(a.frame.minY - b.frame.minY) > 4 { return a.frame.minY < b.frame.minY }
        return a.frame.minX < b.frame.minX
    }
}
