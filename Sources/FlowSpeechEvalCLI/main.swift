// flow-speech-eval — Track B speech robustness and segmentation harness.
//
// For every fixture utterance and voice: synthesize speech with macOS `say` (temporary
// file, deleted afterwards), stream it through the real Argmax pipeline (FlowArgmax
// segmenter → UtteranceAssembler), and record what became final.
//
// Outputs (in --out DIR):
//   asr.csv                      per utterance × voice: reference, finals, #finals, WER
//   <fixture>.<voice>.json       the fixture with each utterance replaced by the first
//                                final transcript, so `flow-bench --pipeline router` can score
//                                routing on real ASR output
//   summary.md                   WER, missed / split utterances per voice and pause length
//
//   ARGMAX_API_KEY=… swift run flow-speech-eval --fixtures F... [--voices Samantha,Daniel]
//       [--rate 180] [--pause-ms 0,400,800] [--hold 0.3] [--limit N] --out DIR
//
// --pause-ms inserts a silence of that length at the middle word boundary of utterances with
// four or more words, to measure commands split by the segmenter. Nothing is executed.

import FlowArgmax
import FlowAudio
import Foundation

var fixturePaths: [String] = []
var voices = ["Samantha"]
var rate = 180
var pauses = [0]
var hold = 0.6
var limit = Int.max
var outDir = "speech-eval"
var itn = false
var minWords = 0

var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--fixtures": if let f = it.next() { fixturePaths.append(f) }
    case "--voices": voices = (it.next() ?? "").split(separator: ",").map(String.init)
    case "--rate": rate = it.next().flatMap(Int.init) ?? rate
    case "--pause-ms": pauses = (it.next() ?? "0").split(separator: ",").compactMap { Int($0) }
    case "--hold": hold = it.next().flatMap(Double.init) ?? hold
    case "--limit": limit = it.next().flatMap(Int.init) ?? limit
    case "--out": outDir = it.next() ?? outDir
    case "--itn": itn = true
    case "--min-words": minWords = it.next().flatMap(Int.init) ?? minWords
    default:
        print("unknown option \(a)")
        exit(2)
    }
}

// MARK: - Helpers

func normalizedTokens(_ s: String) -> [String] {
    let numbers = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
                   "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12"]
    return s.lowercased().replacingOccurrences(of: "’", with: "'")
        .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
        .filter { !$0.isEmpty }
        .map { numbers[$0] ?? $0 }
}

/// Word error rate (edit distance / reference length).
func wer(_ ref: [String], _ hyp: [String]) -> Double {
    guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
    var prev = Array(0...hyp.count)
    for i in 1...ref.count {
        var cur = [i] + Array(repeating: 0, count: hyp.count)
        for j in stride(from: 1, through: hyp.count, by: 1) {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return Double(prev[hyp.count]) / Double(ref.count)
}

func withPause(_ text: String, ms: Int) -> String {
    let words = text.split(separator: " ")
    guard ms > 0, words.count >= 4 else { return text }
    let mid = words.count / 2
    return (words[..<mid] + ["[[slnc \(ms)]]"] + words[mid...]).joined(separator: " ")
}

/// macOS `say` occasionally hangs on its speech-synthesis XPC service (observed: 54 min
/// at 0% CPU). Each attempt gets a deadline; a hung process is killed and retried.
func synthesize(_ text: String, voice: String, rate: Int, to url: URL, attempts: Int = 3, timeout: TimeInterval = 20) -> Bool {
    for _ in 0..<attempts {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-r", String(rate), "-o", url.path, text]
        do { try p.run() } catch { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning {
            p.terminate()
            print("say timed out after \(Int(timeout)) s; retrying")
            continue
        }
        if p.terminationStatus == 0 { return true }
    }
    return false
}

func csvField(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

// MARK: - Run

var evalSettings = ArgmaxSettings.fromEnvironment(input: .microphone(deviceID: nil))
evalSettings.inverseTextNormalization = itn
let transcriber = ArgmaxTranscriber(settings: evalSettings)
setvbuf(stdout, nil, _IOLBF, 0)  // progress visible in redirected logs
do {
    try await transcriber.prepare()
    try await transcriber.setSegmentPolicy(UtteranceSegmenter.Policy(hold: hold))
} catch {
    print("speech setup failed: \(error.userMessage) (\(error))")
    exit(1)
}
print("Argmax \(ArgmaxTranscriberInfo.sdkVersion), voices \(voices), rate \(rate) wpm, pauses \(pauses) ms, hold \(hold) s, ITN \(itn)")

/// Streams one file through Argmax and returns the finalized utterances.
func transcribe(_ url: URL) async -> (finals: [String], error: String?) {
    do {
        try await transcriber.setInput(.file(url, realtime: false, trailingSilence: 1.5))
        var assembler = UtteranceAssembler()
        var finals: [String] = []
        var t = 0.0
        for try await event in try await transcriber.start() {
            t += 0.01
            for case .final(let text, _) in assembler.ingest(event, at: t) { finals.append(text) }
        }
        for case .final(let text, _) in assembler.finish() { finals.append(text) }
        await transcriber.stop()
        return (finals, nil)
    } catch {
        await transcriber.stop()
        return ([], String(describing: error))
    }
}

/// Watchdog: a transcription that does not finish within `seconds` is stopped and reported.
func transcribe(_ url: URL, timeout seconds: Double) async -> (finals: [String], error: String?) {
    await withTaskGroup(of: (finals: [String], error: String?)?.self) { group in
        group.addTask { await transcribe(url) }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        if let first { return first }
        await transcriber.stop()
        return ([], "transcription timed out after \(Int(seconds)) s")
    }
}

let out = URL(fileURLWithPath: outDir)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let tmp = FileManager.default.temporaryDirectory.appending(path: "flow-speech-eval-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

struct Stat { var n = 0; var missed = 0; var split = 0; var exact = 0; var werSum = 0.0 }
var stats: [String: Stat] = [:]  // key: voice|pause
var csv = "fixture,id,voice,pause_ms,reference,finals,n_finals,wer,exact\n"
var failures: [String] = []

for path in fixturePaths {
    guard let data = FileManager.default.contents(atPath: path),
        var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        print("cannot read \(path)")
        exit(1)
    }
    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    for pause in pauses {
        for voice in voices {
            var asrRoot = root
            for section in ["intent", "ambiguous", "contextual"] {
                guard var cases = root[section] as? [[String: Any]] else { continue }
                for i in cases.indices where i < limit {
                    guard let id = cases[i]["id"] as? String, let ref = cases[i]["utterance"] as? String,
                        ref.split(separator: " ").count >= minWords
                    else { continue }
                    let spoken = withPause(ref, ms: pause)
                    let audio = tmp.appending(path: "\(id)-\(voice).aiff")
                    guard synthesize(spoken, voice: voice, rate: rate, to: audio) else {
                        failures.append("\(id) \(voice): say failed")
                        continue
                    }
                    let (finals, error) = await transcribe(audio, timeout: 60)
                    try? FileManager.default.removeItem(at: audio)
                    if let error { failures.append("\(id) \(voice): \(error)") }
                    let hyp = finals.joined(separator: " ")
                    let w = wer(normalizedTokens(ref), normalizedTokens(hyp))
                    let exact = normalizedTokens(ref) == normalizedTokens(hyp) && finals.count == 1
                    var st = stats["\(voice)|\(pause)", default: Stat()]
                    st.n += 1
                    st.missed += finals.isEmpty ? 1 : 0
                    st.split += finals.count > 1 ? 1 : 0
                    st.exact += exact ? 1 : 0
                    st.werSum += w
                    stats["\(voice)|\(pause)"] = st
                    csv += [stem, id, voice, String(pause), csvField(ref), csvField(finals.joined(separator: " | ")),
                            String(finals.count), String(format: "%.3f", w), exact ? "1" : "0"].joined(separator: ",") + "\n"
                    print(String(format: "%@ %@ %4dms %-9@ finals=%d wer=%.2f  “%@”", stem, id, pause, voice, finals.count, w,
                                 finals.joined(separator: " | ")))
                    // What the live pipeline would route first.
                    cases[i]["utterance"] = finals.first ?? ""
                    cases[i]["asrFinals"] = finals
                }
                asrRoot[section] = Array(cases.prefix(limit))
            }
            asrRoot["notes"] = "ASR transcripts (Argmax \(ArgmaxTranscriberInfo.sdkVersion), say voice \(voice), \(rate) wpm, pause \(pause) ms, hold \(hold) s) of \(stem). utterance = first final."
            asrRoot.removeValue(forKey: "malformed")
            if let json = try? JSONSerialization.data(withJSONObject: asrRoot, options: [.prettyPrinted, .sortedKeys]) {
                try? json.write(to: out.appending(path: "\(stem).\(voice).p\(pause).json"))
            }
        }
    }
    root.removeAll()
}

var md = "# Speech evaluation\n\nArgmax \(ArgmaxTranscriberInfo.sdkVersion) `parakeet-v2_476MB`, macOS `say` voices at \(rate) wpm, segment hold \(hold) s, VAD release 0.4 s, ITN \(itn). Synthetic speech; not a substitute for real users.\n\n"
md += "| Voice | Pause (ms) | Utterances | Exact transcript | Mean WER | Missed (0 finals) | Split (>1 final) |\n|---|---|---|---|---|---|---|\n"
for key in stats.keys.sorted() {
    let s = stats[key]!
    let parts = key.split(separator: "|")
    md += String(format: "| %@ | %@ | %d | %d (%.0f%%) | %.3f | %d | %d |\n", String(parts[0]), String(parts[1]), s.n, s.exact,
                 100 * Double(s.exact) / Double(max(s.n, 1)), s.werSum / Double(max(s.n, 1)), s.missed, s.split)
}
if !failures.isEmpty { md += "\nFailures:\n" + failures.map { "- \($0)" }.joined(separator: "\n") + "\n" }
try? csv.write(to: out.appending(path: "asr.csv"), atomically: true, encoding: .utf8)
try? md.write(to: out.appending(path: "summary.md"), atomically: true, encoding: .utf8)
print("\n" + md)
