import FlowCore
import FlowLLM
import FlowRouting
import Foundation

// MARK: - Fixture model

struct BenchmarkFixtures: Decodable {
    let intent: [BenchCase]
    let ambiguous: [BenchCase]
    let contextual: [BenchCase]
    let malformed: [MalformedCase]

    enum CodingKeys: String, CodingKey { case intent, ambiguous, contextual, malformed }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent = try c.decodeIfPresent([BenchCase].self, forKey: .intent) ?? []
        ambiguous = try c.decodeIfPresent([BenchCase].self, forKey: .ambiguous) ?? []
        contextual = try c.decodeIfPresent([BenchCase].self, forKey: .contextual) ?? []
        malformed = try c.decodeIfPresent([MalformedCase].self, forKey: .malformed) ?? []
    }

    static func load(_ url: URL) throws -> BenchmarkFixtures {
        try JSONDecoder().decode(BenchmarkFixtures.self, from: Data(contentsOf: url))
    }

    var categorized: [(Category, [BenchCase])] {
        [(.intent, intent), (.ambiguous, ambiguous), (.contextual, contextual)].filter { !$0.1.isEmpty }
    }
}

/// Task state preceding an utterance (see fixtures/context-benchmark.json).
struct ContextSpec: Decodable, Sendable, Equatable {
    var app: String?
    var people: [String]?
    var message: String?
    var draft: Bool?
    var lastEdited: String?
}

extension ContextSpec {
    /// The router's task context for this case (fresh, so it is never treated as stale).
    var conversation: ConversationContext {
        ConversationContext(
            activeApp: app.flatMap(KnownApp.parse), recentPeople: people ?? [], openMessage: message,
            hasDraft: draft ?? false, lastEditedText: lastEdited, updatedAt: Date())
    }
}

struct BenchCase: Decodable, Sendable {
    let id: String
    let utterance: String
    let tags: [String]?
    let context: ContextSpec?
    let accept: [Matcher]

    /// Clarifying is an acceptable answer for this case.
    var clarificationAccepted: Bool { accept.contains { $0.kind == "clarification" } }
}

struct MalformedCase: Decodable, Sendable {
    let id: String
    let raw: String
    let expectError: String
}

/// Declarative expectation on a validated intent.
struct Matcher: Decodable, Sendable {
    var kind: String?
    var action: String?
    var args: [String: String]?
    var contains: [String: String]?
    var nonEmpty: [String]?

    func matches(_ intent: Intent) -> Bool {
        guard kind != nil || action != nil else { return false }
        if let kind, intent.kind.rawValue != kind { return false }
        if let action {
            if action == "none" {
                if intent.action != nil { return false }
            } else if intent.action?.type.rawValue != action {
                return false
            }
        }
        let actual = intent.action.map(ActionSignature.init)?.args ?? [:]
        for (key, value) in args ?? [:] where actual[key]?.lowercased() != value.lowercased() { return false }
        for (key, value) in contains ?? [:] {
            guard let a = actual[key]?.lowercased(), a.contains(value.lowercased()) else { return false }
        }
        for key in nonEmpty ?? [] where (actual[key] ?? "").isEmpty { return false }
        return true
    }
}

/// Flat, comparable view of a typed action.
struct ActionSignature: Equatable {
    let type: String
    let args: [String: String]

    init(_ action: FlowAction) {
        type = action.type.rawValue
        switch action {
        case .activateApp(let app): args = ["app": app.rawValue]
        case .moveWindow(let w, let p): args = ["window": w.signature, "position": p.rawValue]
        case .resizeWindow(let w, let c): args = ["window": w.signature, "change": c.rawValue]
        case .tileWindows(let l, let r): args = ["left": l.rawValue, "right": r.rawValue]
        case .clickElement(let label), .focus(let label): args = ["label": label]
        case .scroll(let d): args = ["direction": d.rawValue]
        case .insertText(let t): args = ["text": t]
        case .replaceText(let old, let new): args = ["old": old, "new": new]
        case .createDraft(let r, let c): args = ["recipient": r, "content": c]
        case .readMessage(let q): args = ["query": q]
        case .queryCalendar(let t): args = ["time": t]
        case .showCalendar(let d): args = ["date": d]
        case .requestReview, .requestSend: args = [:]
        case .editText(let command): args = ["command": command]
        case .minimizeWindow(let w), .restoreWindow(let w), .closeWindow(let w): args = ["window": w.signature]
        case .listWindows, .showNumbers, .hideNumbers: args = [:]
        case .chooseNumber(let n): args = ["number": String(n)]
        }
    }

    var description: String {
        let inner = args.keys.sorted().map { "\($0)=\(args[$0]!)" }.joined(separator: "; ")
        return inner.isEmpty ? type : "\(type)(\(inner))"
    }
}

extension WindowTarget {
    var signature: String {
        switch self {
        case .active: "active"
        case .app(let app): app.rawValue
        }
    }
}

extension ClassificationError {
    /// Case name without payload, e.g. "malformedJSON".
    var caseName: String {
        let full = String(describing: self)
        return full.firstIndex(of: "(").map { String(full[..<$0]) } ?? full
    }

    /// Model output problems the validator caught (safe: nothing reaches the executor).
    var isValidatorRejection: Bool {
        switch self {
        case .malformedJSON, .schemaViolation, .unsupportedAction, .unsupportedTarget, .inconsistentIntent,
            .emptyResponse:
            true
        default: false
        }
    }
}

// MARK: - Results

enum Category: String { case intent, ambiguous, contextual }

enum Outcome: String {
    case pass, wrong, rejected, error
}

/// What one classification produced, independent of which classifier ran.
struct BenchResult: Sendable {
    let outcome: Result<Intent, ClassificationError>
    /// Bonsai calls made (empty for deterministic routes).
    let attempts: [ClassificationTrace.Attempt]
    /// Which stage produced the answer ("model", "fast_path", "context", "clarify", …).
    let route: String
    /// Wall-clock time for the whole classification.
    let latency: Duration
}

struct Row {
    let model: String
    let category: Category
    let id: String
    let tags: [String]
    let run: Int
    let utterance: String
    let clarificationAccepted: Bool
    let outcome: Outcome
    let intent: Intent?
    let error: ClassificationError?
    let attempts: [ClassificationTrace.Attempt]
    let route: String
    let latency: Duration

    var signature: String {
        if let intent {
            return "\(intent.kind.rawValue)|" + (intent.action.map { ActionSignature($0).description } ?? "none")
        }
        return "error|\(error?.caseName ?? "?")"
    }

    /// A validated action that the case does not accept: the dangerous failure.
    var isUnsafeGuess: Bool { outcome == .wrong && intent?.action != nil }
    var isClarification: Bool { intent?.kind == .clarification }

    /// Wire-level conformance of the first attempt.
    var firstAttemptJSONValid: Bool? {
        guard let first = attempts.first else { return nil }
        switch first.error {
        case .malformedJSON, .emptyResponse: return false
        case .serverUnavailable, .timedOut, .httpStatus, .modelMismatch, .cancelled: return nil
        default: return true
        }
    }

    /// Exact wire schema: the five string fields, no extras, allowed `kind`. Empty or
    /// over-long *arguments* are validator (semantic) rejections, not schema failures.
    var firstAttemptSchemaValid: Bool? {
        guard let json = firstAttemptJSONValid else { return nil }
        if case .schemaViolation(let why) = attempts.first?.error, why.contains("field") || why.contains("kind") {
            return false
        }
        return json
    }

    var firstAttemptAccepted: Bool? {
        guard firstAttemptJSONValid != nil else { return nil }
        return attempts.first?.error == nil
    }
}

extension ClassificationTrace {
    func benchResult(route: String = "model", latency: Duration? = nil) -> BenchResult {
        BenchResult(
            outcome: outcome, attempts: attempts, route: route,
            latency: latency ?? attempts.reduce(Duration.zero) { $0 + $1.latency })
    }
}

func classify(row model: String, _ c: BenchCase, _ category: Category, run: Int, _ result: BenchResult) -> Row {
    let (outcome, intent, error): (Outcome, Intent?, ClassificationError?)
    switch result.outcome {
    case .success(let i):
        (outcome, intent, error) = (c.accept.contains { $0.matches(i) } ? .pass : .wrong, i, nil)
    case .failure(let e):
        (outcome, intent, error) = (e.isValidatorRejection ? .rejected : .error, nil, e)
    }
    return Row(
        model: model, category: category, id: c.id, tags: c.tags ?? [], run: run, utterance: c.utterance,
        clarificationAccepted: c.clarificationAccepted, outcome: outcome, intent: intent, error: error,
        attempts: result.attempts, route: result.route, latency: result.latency)
}

/// Offline: every malformed output must be rejected with the expected error.
func checkMalformed(_ cases: [MalformedCase], modelID: String) -> [(MalformedCase, String, Bool)] {
    cases.map { c in
        do throws(ClassificationError) {
            let intent = try IntentValidator.validate(c.raw, modelID: modelID)
            return (c, "ACCEPTED \(intent.kind.rawValue)", false)
        } catch {
            return (c, error.caseName, error.caseName == c.expectError)
        }
    }
}

// MARK: - Statistics and reporting

extension Duration {
    var ms: Double {
        let c = components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let rank = p / 100 * Double(sorted.count - 1)
    let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
}

func pct(_ n: Int, _ d: Int) -> String {
    d == 0 ? "n/a" : String(format: "%d/%d (%.0f%%)", n, d, 100 * Double(n) / Double(d))
}

func csvField(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
}

func csv(_ rows: [Row]) -> String {
    var out = "model,category,id,tags,run,utterance,outcome,unsafe,route,kind,action,summary,error,attempts,latency_ms,first_attempt_ms,raw_first_attempt\n"
    for r in rows {
        let fields: [String] = [
            r.model, r.category.rawValue, r.id, r.tags.joined(separator: " "), String(r.run), csvField(r.utterance),
            r.outcome.rawValue, r.isUnsafeGuess ? "1" : "0", r.route, r.intent?.kind.rawValue ?? "",
            csvField(r.intent?.action.map { ActionSignature($0).description } ?? ""),
            csvField(r.intent?.summary ?? ""),
            csvField(r.error.map { String(describing: $0) } ?? ""), String(r.attempts.count),
            String(format: "%.1f", r.latency.ms),
            String(format: "%.0f", r.attempts.first?.latency.ms ?? 0),
            csvField(r.attempts.first?.rawContent ?? ""),
        ]
        out += fields.joined(separator: ",") + "\n"
    }
    return out
}

func summary(
    model: String, label: String, rows: [Row], runs: Int, warmup: Duration?, malformed: [(MalformedCase, String, Bool)]
) -> String {
    var s = "## \(label) — \(model)\n\n"
    func count(_ rs: [Row], _ o: Outcome) -> Int { rs.filter { $0.outcome == o }.count }

    s += "| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |\n|---|---|---|---|---|\n"
    for category in [Category.intent, .ambiguous, .contextual] {
        let set = rows.filter { $0.category == category }
        guard !set.isEmpty else { continue }
        let cases = set.count / max(runs, 1)
        s += "| \(category.rawValue) (\(cases)) × \(runs) | \(pct(count(set, .pass), set.count)) | \(count(set, .wrong)) (\(set.filter(\.isUnsafeGuess).count)) | \(count(set, .rejected)) | \(count(set, .error)) |\n"
    }
    let tags = Set(rows.flatMap(\.tags)).sorted()
    for tag in tags {
        let tagged = rows.filter { $0.tags.contains(tag) }
        s += "| tag `\(tag)` | \(pct(count(tagged, .pass), tagged.count)) | \(count(tagged, .wrong)) (\(tagged.filter(\.isUnsafeGuess).count)) | \(count(tagged, .rejected)) | \(count(tagged, .error)) |\n"
    }

    // Safety and clarification.
    let unsafe = rows.filter(\.isUnsafeGuess)
    let shouldClarify = rows.filter { $0.clarificationAccepted }
    let clarifiedWhenOK = shouldClarify.filter(\.isClarification).count
    let overAsked = rows.filter { !$0.clarificationAccepted && $0.isClarification }.count
    s += "\nUnsafe guesses (validated action outside the accept set): **\(unsafe.count)/\(rows.count)**. "
    s += "Clarification on cases where it is acceptable: \(pct(clarifiedWhenOK, shouldClarify.count)). "
    s += "Clarification where a definite answer was expected (over-asking): \(overAsked).\n"

    // Routes.
    let routes = Dictionary(grouping: rows, by: \.route).mapValues(\.count)
    s += "\nRoutes: " + routes.keys.sorted().map { "\($0) \(pct(routes[$0]!, rows.count))" }.joined(separator: ", ") + ".\n"

    // Consistency across repeated runs.
    let byCase = Dictionary(grouping: rows, by: \.id)
    let unstable = byCase.filter { Set($0.value.map(\.signature)).count > 1 }.keys.sorted()
    s += "\nConsistency: \(pct(byCase.count - unstable.count, byCase.count)) cases gave an identical result in every run"
    s += unstable.isEmpty ? ".\n" : "; unstable: \(unstable.joined(separator: ", ")).\n"

    // Structured output conformance (first attempt only, before any retry).
    let measured = rows.compactMap(\.firstAttemptJSONValid)
    if !measured.isEmpty {
        let schema = rows.compactMap(\.firstAttemptSchemaValid)
        let accepted = rows.compactMap(\.firstAttemptAccepted)
        let retried = rows.filter { $0.attempts.count > 1 }.count
        s += "\nJSON-schema conformance (first attempt, \(measured.count) model calls): "
        s += "parseable JSON object \(pct(measured.filter { $0 }.count, measured.count)), "
        s += "exact schema fields \(pct(schema.filter { $0 }.count, schema.count)), "
        s += "passed strict validator \(pct(accepted.filter { $0 }.count, accepted.count)); retries used: \(retried).\n"
    }

    // Latency: end-to-end per classification, and per model call.
    let total = rows.map(\.latency.ms)
    s += String(
        format: "\nLatency per command (all routes): p50 %.1f ms, p95 %.1f ms, max %.1f ms (n=%d).",
        percentile(total, 50), percentile(total, 95), total.max() ?? .nan, total.count)
    for route in routes.keys.sorted() {
        let l = rows.filter { $0.route == route }.map(\.latency.ms)
        s += String(format: " `%@` p50 %.1f ms.", route, percentile(l, 50))
    }
    let calls = rows.flatMap { $0.attempts.map(\.latency.ms) }
    if !calls.isEmpty {
        s += String(format: " Model call p50 %.0f ms, p95 %.0f ms (n=%d).", percentile(calls, 50), percentile(calls, 95), calls.count)
    }
    if let warmup { s += String(format: " Warm-up request: %.0f ms.", warmup.ms) }
    s += "\n"

    if !malformed.isEmpty {
        let ok = malformed.filter(\.2).count
        s += "\nMalformed model outputs rejected with the expected error: \(pct(ok, malformed.count)).\n"
        for (c, got, pass) in malformed where !pass { s += "- \(c.id): expected \(c.expectError), got \(got)\n" }
    }

    // Failures detail (first run; results are deterministic across runs unless listed unstable).
    let failures = rows.filter { $0.outcome != .pass && ($0.run == 1 || unstable.contains($0.id)) }
    if !failures.isEmpty {
        s += "\nNon-passing results (run 1, plus every run of unstable cases):\n\n| Case | Utterance | Run | Outcome | Route | Got |\n|---|---|---|---|---|---|\n"
        for r in failures.sorted(by: { ($0.id, $0.run) < ($1.id, $1.run) }) {
            var got = r.intent.map { i in "\(i.kind.rawValue) " + (i.action.map { ActionSignature($0).description } ?? "none") }
                ?? r.error.map { String(describing: $0) } ?? "?"
            if r.isClarification, let q = r.intent?.summary { got += " “\(q)”" }
            let outcome = r.isUnsafeGuess ? "**unsafe**" : r.outcome.rawValue
            s += "| \(r.id) | \(r.utterance) | \(r.run) | \(outcome) | \(r.route) | \(got.replacingOccurrences(of: "|", with: "/")) |\n"
        }
    }
    return s
}
