// flow-bench — Bonsai / intent-router benchmark (Track B).
//
//   swift run flow-bench [--fixtures FILE]... [--runs 3] [--pipeline bonsai|router]
//                        [--model ternary-bonsai-2-2b-mlx]... [--out DIR]
//   swift run flow-bench --probe "open notes" [--model ID]    # one timed request
//
// Classification only; nothing is executed. `bonsai` needs LM Studio on localhost;
// `router` needs it only for utterances that reach the model.

import FlowCore
import FlowLLM
import FlowRouting
import Foundation

var fixturePaths: [String] = []
var runs = 3
var models: [String] = []
var outDir: String?
var probe: String?
var pipeline = "bonsai"
var promptVersion = "v2"

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--fixtures": if let f = args.next() { fixturePaths.append(f) }
    case "--runs": runs = args.next().flatMap(Int.init) ?? runs
    case "--model": if let m = args.next() { models.append(m) }
    case "--out": outDir = args.next()
    case "--probe": probe = args.next()
    case "--pipeline": pipeline = args.next() ?? pipeline
    case "--prompt": promptVersion = args.next() ?? promptVersion
    default:
        print("unknown option \(arg)")
        exit(2)
    }
}
if models.isEmpty { models = [LMStudioConfiguration.defaultModelID] }
if fixturePaths.isEmpty { fixturePaths = ["fixtures/bonsai-benchmark.json"] }

func bonsai(_ model: String, prompt promptVersion: String) -> BonsaiIntentClassifier {
    do {
        let prompt: String
        switch promptVersion {
        case "v1": prompt = IntentSchema.systemPromptV1
        case "v2": prompt = IntentSchema.systemPromptV2
        case "v3": prompt = IntentSchema.systemPromptV3
        default:
            print("unknown --prompt \(promptVersion) (expected v1 or v2)")
            exit(2)
        }
        return BonsaiIntentClassifier(
            client: LMStudioClient(configuration: try LMStudioConfiguration(modelID: model, requestTimeout: 120)),
            systemPrompt: prompt)
    } catch {
        print("invalid configuration: \(error.userMessage)")
        exit(1)
    }
}

typealias BenchClassifier = @Sendable (BenchCase) async -> BenchResult

func makeClassifier(_ pipeline: String, model: String, prompt: String) -> BenchClassifier {
    switch pipeline {
    case "bonsai":
        let c = bonsai(model, prompt: prompt)
        // Baseline: Bonsai alone; task context is not available to it.
        return { benchCase in
            let start = ContinuousClock.now
            let trace = await c.classifyTraced(benchCase.utterance)
            return trace.benchResult(latency: ContinuousClock.now - start)
        }
    case "router":
        let core = IntentRouterCore(model: bonsai(model, prompt: prompt))
        return { benchCase in
            let start = ContinuousClock.now
            let decision = await core.route(benchCase.utterance, context: benchCase.context?.conversation ?? .empty)
            return BenchResult(
                outcome: decision.outcome, attempts: decision.trace?.attempts ?? [], route: decision.stage.rawValue,
                latency: ContinuousClock.now - start)
        }
    default:
        print("unknown --pipeline \(pipeline) (expected bonsai or router)")
        exit(2)
    }
}

if let probe {
    let trace = await bonsai(models[0], prompt: promptVersion).classifyTraced(probe)
    for (i, a) in trace.attempts.enumerated() {
        print(String(format: "attempt %d: %.0f ms %@", i + 1, a.latency.ms, a.error.map { "\($0)" } ?? "ok"))
    }
    print("outcome: \(trace.outcome)")
    exit(0)
}

var sets: [(path: String, fixtures: BenchmarkFixtures)] = []
for path in fixturePaths {
    do {
        sets.append((path, try BenchmarkFixtures.load(URL(fileURLWithPath: path))))
    } catch {
        print("cannot load fixtures \(path): \(error)")
        exit(1)
    }
}

var report = "# Intent benchmark (`--pipeline \(pipeline) --prompt \(promptVersion)`)\n\nGenerated \(ISO8601DateFormatter().string(from: Date())) by `flow-bench`, \(runs) runs per prompt, temperature 0, strict JSON schema.\n\n"
var allRows: [Row] = []

for model in models {
    let classifyCase = makeClassifier(pipeline, model: model, prompt: promptVersion)
    print("== \(model) (\(pipeline))")
    let warm = await bonsai(model, prompt: promptVersion).classifyTraced("open notes")
    let warmup = warm.attempts.first?.latency
    if case .failure(let e) = warm.outcome, !e.isValidatorRejection {
        print("model unavailable: \(e.userMessage) (\(e))")
        report += "## \(model)\n\nNot benchmarked: \(e.userMessage) (`\(e)`)\n\n"
        continue
    }

    for set in sets {
        var rows: [Row] = []
        for run in 1...runs {
            for (category, cases) in set.fixtures.categorized {
                for benchCase in cases {
                    let result = await classifyCase(benchCase)
                    let row = classify(row: model, benchCase, category, run: run, result)
                    rows.append(row)
                    print(String(
                        format: "run %d %@ %-8@ %-9@ %8.1f ms  %@", run, benchCase.id, row.outcome.rawValue,
                        row.route, row.latency.ms, row.signature))
                }
            }
        }
        allRows += rows
        let malformed = checkMalformed(set.fixtures.malformed, modelID: model)
        let label = URL(fileURLWithPath: set.path).lastPathComponent
        report += summary(model: model, label: label, rows: rows, runs: runs, warmup: warmup, malformed: malformed) + "\n"
    }
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
