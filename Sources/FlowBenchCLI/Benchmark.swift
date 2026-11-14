import FlowCore
import FlowLLM
import Foundation

// MARK: - Fixture model

struct BenchmarkFixtures: Decodable {
    let intent: [BenchCase]
    let ambiguous: [BenchCase]
    let malformed: [MalformedCase]

    static func load(_ url: URL) throws -> BenchmarkFixtures {
        try JSONDecoder().decode(BenchmarkFixtures.self, from: Data(contentsOf: url))
    }
}

struct BenchCase: Decodable, Sendable {
    let id: String
    let utterance: String
    let tags: [String]?
    let accept: [Matcher]
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
        case .requestReview, .requestSend: args = [:]
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

enum Category: String { case intent, ambiguous }

enum Outcome: String {
    case pass, wrong, rejected, error
}

struct Row {
    let model: String
    let category: Category
    let id: String
    let tags: [String]
    let run: Int
    let utterance: String
    let outcome: Outcome
    let intent: Intent?
    let error: ClassificationError?
    let attempts: [ClassificationTrace.Attempt]
    let latency: Duration

    var signature: String {
        if let intent {
            return "\(intent.kind.rawValue)|" + (intent.action.map { ActionSignature($0).description } ?? "none")
        }
        return "error|\(error?.caseName ?? "?")"
    }

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

func classify(row model: String, _ c: BenchCase, _ category: Category, run: Int, _ trace: ClassificationTrace) -> Row {
    let latency = trace.attempts.reduce(Duration.zero) { $0 + $1.latency }
    switch trace.outcome {
    case .success(let intent):
        let ok = c.accept.contains { $0.matches(intent) }
        return Row(
            model: model, category: category, id: c.id, tags: c.tags ?? [], run: run, utterance: c.utterance,
            outcome: ok ? .pass : .wrong, intent: intent, error: nil, attempts: trace.attempts, latency: latency)
    case .failure(let error):
        return Row(
            model: model, category: category, id: c.id, tags: c.tags ?? [], run: run, utterance: c.utterance,
            outcome: error.isValidatorRejection ? .rejected : .error, intent: nil, error: error,
            attempts: trace.attempts, latency: latency)
    }
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
    var out = "model,category,id,tags,run,utterance,outcome,kind,action,error,attempts,latency_ms,first_attempt_ms,raw_first_attempt\n"
    for r in rows {
        let fields: [String] = [
            r.model, r.category.rawValue, r.id, r.tags.joined(separator: " "), String(r.run), csvField(r.utterance),
            r.outcome.rawValue, r.intent?.kind.rawValue ?? "",
            csvField(r.intent?.action.map { ActionSignature($0).description } ?? ""),
            csvField(r.error.map { String(describing: $0) } ?? ""), String(r.attempts.count),
            String(format: "%.0f", r.latency.ms),
            String(format: "%.0f", r.attempts.first?.latency.ms ?? 0),
            csvField(r.attempts.first?.rawContent ?? ""),
        ]
        out += fields.joined(separator: ",") + "\n"
    }
    return out
}

func summary(
    model: String, rows: [Row], runs: Int, warmup: Duration?, malformed: [(MalformedCase, String, Bool)]
) -> String {
    var s = "## \(model)\n\n"
    let intent = rows.filter { $0.category == .intent }
    let ambiguous = rows.filter { $0.category == .ambiguous }
    func count(_ rs: [Row], _ o: Outcome) -> Int { rs.filter { $0.outcome == o }.count }

    s += "| Set | Pass | Wrong action | Rejected by validator | Transport error |\n|---|---|---|---|---|\n"
    for (name, set) in [("Intent (30)", intent), ("Ambiguous (15)", ambiguous)] {
        s += "| \(name) × \(runs) runs | \(pct(count(set, .pass), set.count)) | \(count(set, .wrong)) | \(count(set, .rejected)) | \(count(set, .error)) |\n"
    }
    for tag in ["email-search", "draft-content"] {
        let tagged = intent.filter { $0.tags.contains(tag) }
        s += "| tag `\(tag)` | \(pct(count(tagged, .pass), tagged.count)) | \(count(tagged, .wrong)) | \(count(tagged, .rejected)) | \(count(tagged, .error)) |\n"
    }
    let clarified = ambiguous.filter { $0.intent?.kind == .clarification }.count
    s += "\nAmbiguous answered with `clarification`: \(pct(clarified, ambiguous.count)). "
    s += "Unsafe ambiguous (validated action outside the accept set): \(count(ambiguous, .wrong)).\n"

    // Consistency across repeated runs.
    let byCase = Dictionary(grouping: rows, by: \.id)
    let unstable = byCase.filter { Set($0.value.map(\.signature)).count > 1 }.keys.sorted()
    s += "\nConsistency: \(pct(byCase.count - unstable.count, byCase.count)) cases gave an identical result in every run"
    s += unstable.isEmpty ? ".\n" : "; unstable: \(unstable.joined(separator: ", ")).\n"

    // Structured output conformance (first attempt only, before any retry).
    let measured = rows.compactMap(\.firstAttemptJSONValid)
    let schema = rows.compactMap(\.firstAttemptSchemaValid)
    let accepted = rows.compactMap(\.firstAttemptAccepted)
    let retried = rows.filter { $0.attempts.count > 1 }.count
    s += "\nJSON-schema conformance (first attempt, \(measured.count) model calls): "
    s += "parseable JSON object \(pct(measured.filter { $0 }.count, measured.count)), "
    s += "exact schema fields \(pct(schema.filter { $0 }.count, schema.count)), "
    s += "passed strict validator \(pct(accepted.filter { $0 }.count, accepted.count)); retries used: \(retried).\n"

    // Latency of warm model calls.
    let latencies = rows.flatMap { $0.attempts.map(\.latency.ms) }
    s += String(
        format: "\nWarm latency per model call: p50 %.0f ms, p95 %.0f ms, max %.0f ms (n=%d).",
        percentile(latencies, 50), percentile(latencies, 95), latencies.max() ?? .nan, latencies.count)
    if let warmup { s += String(format: " Warm-up request: %.0f ms.", warmup.ms) }
    s += "\n"

    // Malformed outputs.
    let malformedOK = malformed.filter(\.2).count
    s += "\nMalformed model outputs rejected with the expected error: \(pct(malformedOK, malformed.count)).\n"
    for (c, got, ok) in malformed where !ok { s += "- \(c.id): expected \(c.expectError), got \(got)\n" }

    // Failures detail (first run each).
    let failures = rows.filter { $0.outcome != .pass }
    if !failures.isEmpty {
        s += "\nNon-passing results (all runs):\n\n| Case | Utterance | Run | Outcome | Got |\n|---|---|---|---|---|\n"
        for r in failures.sorted(by: { ($0.id, $0.run) < ($1.id, $1.run) }) {
            let got = r.intent.map { i in "\(i.kind.rawValue) " + (i.action.map { ActionSignature($0).description } ?? "none") }
                ?? r.error.map { String(describing: $0) } ?? "?"
            s += "| \(r.id) | \(r.utterance) | \(r.run) | \(r.outcome.rawValue) | \(got.replacingOccurrences(of: "|", with: "/")) |\n"
        }
    }
    return s
}
