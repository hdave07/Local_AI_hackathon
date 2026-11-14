// flow-bench — T-002 Bonsai + LM Studio benchmark (Track B).
//
//   swift run flow-bench [--fixtures fixtures/bonsai-benchmark.json] [--runs 3]
//                        [--model ternary-bonsai-2-2b-mlx]... [--out DIR]
//   swift run flow-bench --probe "open notes" [--model ID]    # one timed request
//
// Classification only; nothing is executed. Requires LM Studio on localhost.

import FlowCore
import FlowLLM
import Foundation

var fixturesPath = "fixtures/bonsai-benchmark.json"
var runs = 3
var models: [String] = []
var outDir: String?
var probe: String?

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--fixtures": fixturesPath = args.next() ?? fixturesPath
    case "--runs": runs = args.next().flatMap(Int.init) ?? runs
    case "--model": if let m = args.next() { models.append(m) }
    case "--out": outDir = args.next()
    case "--probe": probe = args.next()
    default:
        print("unknown option \(arg)")
        exit(2)
    }
}
if models.isEmpty { models = [LMStudioConfiguration.defaultModelID] }

func classifier(_ model: String) -> BonsaiIntentClassifier {
    do {
        return BonsaiIntentClassifier(
            client: LMStudioClient(configuration: try LMStudioConfiguration(modelID: model, requestTimeout: 120)))
    } catch {
        print("invalid configuration: \(error.userMessage)")
        exit(1)
    }
}

if let probe {
    let trace = await classifier(models[0]).classifyTraced(probe)
    for (i, a) in trace.attempts.enumerated() {
        print(String(format: "attempt %d: %.0f ms %@", i + 1, a.latency.ms, a.error.map { "\($0)" } ?? "ok"))
    }
    print("outcome: \(trace.outcome)")
    exit(0)
}

let fixtures: BenchmarkFixtures
do {
    fixtures = try BenchmarkFixtures.load(URL(fileURLWithPath: fixturesPath))
} catch {
    print("cannot load fixtures: \(error)")
    exit(1)
}
print("fixtures: \(fixtures.intent.count) intent, \(fixtures.ambiguous.count) ambiguous, \(fixtures.malformed.count) malformed; runs=\(runs)")

var report = "# T-002 Bonsai benchmark\n\nGenerated \(ISO8601DateFormatter().string(from: Date())) by `flow-bench`, \(runs) runs per prompt, temperature 0, strict JSON schema.\n\n"
var allRows: [Row] = []

for model in models {
    let c = classifier(model)
    print("== \(model)")
    let warm = await c.classifyTraced("open notes")
    let warmup = warm.attempts.first?.latency
    if case .failure(let e) = warm.outcome, !e.isValidatorRejection {
        print("model unavailable: \(e.userMessage) (\(e))")
        report += "## \(model)\n\nNot benchmarked: \(e.userMessage) (`\(e)`)\n\n"
        continue
    }

    var rows: [Row] = []
    for run in 1...runs {
        for (category, cases) in [(Category.intent, fixtures.intent), (.ambiguous, fixtures.ambiguous)] {
            for benchCase in cases {
                let trace = await c.classifyTraced(benchCase.utterance)
                let row = classify(row: model, benchCase, category, run: run, trace)
                rows.append(row)
                print(String(
                    format: "run %d %@ %-5@ %6.0f ms  %@", run, benchCase.id, row.outcome.rawValue, row.latency.ms,
                    row.signature))
            }
        }
    }
    allRows += rows
    let malformed = checkMalformed(fixtures.malformed, modelID: model)
    report += summary(model: model, rows: rows, runs: runs, warmup: warmup, malformed: malformed) + "\n"
}

print("\n" + report)
if let outDir {
    let dir = URL(fileURLWithPath: outDir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do {
        try csv(allRows).write(to: dir.appending(path: "results.csv"), atomically: true, encoding: .utf8)
        try report.write(to: dir.appending(path: "summary.md"), atomically: true, encoding: .utf8)
        print("wrote \(dir.path)/results.csv and summary.md")
    } catch {
        print("could not write results: \(error)")
    }
}
