// flow-voice — Track B developer harness.
//
//   Microphone (or audio file) → Argmax Pro streaming ASR → stable utterance →
//   deterministic control phrases / Bonsai via LM Studio → validated typed intent →
//   MockActionConsumer.
//
// NOTHING IS EXECUTED. No app is opened, no window moves, no mail is sent.
//
// Usage:
//   ARGMAX_API_KEY=ax_… swift run flow-voice [--file PATH] [--fast] [--once]
//                                            [--max-seconds N] [--model NAME] [--verbose]
// Environment: ARGMAX_API_KEY (required), HF_TOKEN (optional),
//              FLOW_LMSTUDIO_URL, FLOW_MODEL_ID (localhost only).

import FlowArgmax
import FlowAudio
import FlowCore
import FlowLLM
import Foundation

struct Options {
    var file: URL?
    var realtime = true
    var once = false
    var maxSeconds: Double?
    var model: String?
    var mode: String?
    var verbose = false

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var it = args.dropFirst().makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--file": o.file = it.next().map { URL(fileURLWithPath: $0) }
            case "--fast": o.realtime = false
            case "--once": o.once = true
            case "--max-seconds": o.maxSeconds = it.next().flatMap(Double.init)
            case "--model": o.model = it.next()
            case "--mode": o.mode = it.next()
            case "--verbose": o.verbose = true
            case "-h", "--help":
                print("usage: flow-voice [--file PATH] [--fast] [--once] [--max-seconds N] [--model NAME] [--mode always|voice|battery] [--verbose]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("unknown option \(arg)\n".utf8))
                exit(2)
            }
        }
        return o
    }
}

func line(_ s: String) {
    let stamp = String(format: "%7.2f", ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 10_000))
    print("[\(stamp)] \(s)")
    fflush(stdout)
}

func describe(_ routed: RoutedUtterance) -> String {
    let ms = Int(routed.routingLatency.components.seconds * 1000)
        + Int(routed.routingLatency.components.attoseconds / 1_000_000_000_000_000)
    switch routed.outcome {
    case .success(let intent):
        let what = intent.action.map { "\($0.type.rawValue) → \($0.targetDescription) [risk \($0.risk.rawValue)]" }
            ?? intent.control.map { "control: \($0.rawValue)" } ?? intent.kind.rawValue
        return "\(what) via \(routed.routedBy == .model ? "Bonsai" : "deterministic") in \(ms) ms"
    case .failure(let error):
        return "REJECTED: \(error.userMessage) (\(error)) after \(ms) ms"
    }
}

let options = Options.parse(CommandLine.arguments)
let env = ProcessInfo.processInfo.environment

// Language model (unchanged FlowLLM classifier).
let lmConfig: LMStudioConfiguration
do {
    lmConfig = try LMStudioConfiguration(
        baseURL: env["FLOW_LMSTUDIO_URL"].flatMap(URL.init(string:)) ?? LMStudioConfiguration.defaultBaseURL,
        modelID: env["FLOW_MODEL_ID"] ?? LMStudioConfiguration.defaultModelID)
} catch {
    print("Invalid model configuration: \(error.userMessage)")
    exit(1)
}
let classifier = BonsaiIntentClassifier(client: LMStudioClient(configuration: lmConfig))

// Speech.
let input: ArgmaxSettings.Input = options.file.map { .file($0, realtime: options.realtime, trailingSilence: 3.0) }
    ?? .microphone(deviceID: nil)
var settings = ArgmaxSettings.fromEnvironment(input: input)
if let model = options.model { settings.model = model }
switch options.mode {
case nil: break
case "always": settings.streamMode = .alwaysOn
case "voice": settings.streamMode = .voiceTriggered
case "battery": settings.streamMode = .batteryOptimized
case let other?:
    print("unknown --mode \(other)")
    exit(2)
}
settings.verbose = options.verbose
let transcriber = ArgmaxTranscriber(settings: settings)

let done = LockedFlag()
let sink = MockActionConsumer { routed in
    line("MOCK CONSUMER received (NOT EXECUTED): \(describe(routed))")
}
let pipeline = VoicePipeline(
    transcriber: transcriber,
    permission: settings.usesMicrophone ? SystemMicrophonePermission() : nil,
    classifier: classifier,
    sink: sink)

line("flow-voice: Argmax SDK \(ArgmaxTranscriberInfo.sdkVersion), model \(settings.model), LLM \(lmConfig.modelID)")
line(settings.usesMicrophone ? "input: default microphone — speak a command (e.g. “Open Notes”)" : "input: \(options.file!.path)")

let observer = Task {
    var lastPartial = ""
    for await event in pipeline.events {
        switch event {
        case .state(let state):
            switch state {
            case .listening: line("● listening")
            case .preparing: line("… preparing speech model (first load can take 15–90 s)")
            case .failed(let error): line("✖ \(error.userMessage) (\(error))")
            case .stopped: line("■ stopped")
            default: break
            }
        case .partial(let partial):
            if partial.displayText != lastPartial {
                lastPartial = partial.displayText
                line("  partial: \(partial.confirmed)\(partial.hypothesis.isEmpty ? "" : " ‹\(partial.hypothesis)›")")
            }
        case .incomplete(let partial):
            line("  dropped unconfirmed speech (not routed): “\(partial.displayText)”")
        case .finalized(let utterance):
            line("▶ FINAL: “\(utterance.stableText)” lang=\(utterance.language ?? "?")")
        case .routed:
            if options.once, done.setOnce() { Task { await pipeline.stop() } }
        }
    }
}

if let seconds = options.maxSeconds {
    Task {
        try? await Task.sleep(for: .seconds(seconds))
        line("max duration reached")
        await pipeline.stop()
    }
}

let started = ContinuousClock.now
var exitCode: Int32 = 0
do {
    try await pipeline.run()
} catch {
    exitCode = 1
}
let diagnostics = await transcriber.diagnostics
if let d = diagnostics.downloadDuration { line("model download/verify: \(d)") }
if let l = diagnostics.loadDuration { line("model load: \(l)") }
if let lic = diagnostics.lastLicenseEvent { line("license: \(lic)") }
let actions = await sink.received
line("session \(ContinuousClock.now - started); consumer received \(actions.count) intent(s); nothing executed")
try? await Task.sleep(for: .milliseconds(50))
observer.cancel()
exit(exitCode)

final class LockedFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    /// Returns true the first time only.
    func setOnce() -> Bool { lock.withLock { defer { value = true }; return !value } }
}
