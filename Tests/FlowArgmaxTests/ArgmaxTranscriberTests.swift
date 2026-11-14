import Argmax
@testable import FlowArgmax
import FlowAudio
import FlowCore
import FlowLLM
import Foundation
import Testing

@Suite("Argmax adapter (no license needed)")
struct ArgmaxAdapterTests {
    @Test func missingKeyFailsBeforeAnyNetworkOrModelWork() async {
        let t = ArgmaxTranscriber(settings: ArgmaxSettings(apiKey: nil))
        await #expect(throws: AudioError.licenseMissing) { try await t.prepare() }
        let blank = ArgmaxTranscriber(settings: ArgmaxSettings(apiKey: "   "))
        await #expect(throws: AudioError.licenseMissing) { try await blank.prepare() }
        #expect(await t.diagnostics.modelFolder == nil)
    }

    @Test func startWithoutKeyAlsoReportsLicenseMissing() async {
        let t = ArgmaxTranscriber(settings: ArgmaxSettings(apiKey: nil))
        await #expect(throws: AudioError.licenseMissing) { _ = try await t.start() }
    }

    @Test func sdkErrorsMapToTypedAudioErrors() {
        typealias T = ArgmaxTranscriber
        #expect(T.map(ArgmaxError.invalidLicense("expired"), during: .load) == .licenseRejected("expired"))
        #expect(T.map(ArgmaxError.modelUnavailable("gone"), during: .download) == .modelUnavailable("gone"))
        #expect(T.map(ArgmaxError.generic("Record permission denied"), during: .stream) == .microphoneDenied)
        #expect(T.map(ArgmaxError.generic("boom"), during: .stream) == .engineFailed("boom"))
        #expect(T.map(ArgmaxError.generic("offline"), during: .download) == .modelUnavailable("offline"))
        #expect(T.map(ArgmaxError.invalidConfiguration("bad"), during: .stream) == .engineFailed("bad"))
        #expect(T.map(CancellationError(), during: .stream) == .cancelled)
        #expect(T.map(AudioError.noInputDevice, during: .stream) == .noInputDevice)
        if case .engineFailed = T.map(LiveTranscriberError.streamAlreadyActive("x"), during: .stream) {} else {
            Issue.record("LiveTranscriberError should map to engineFailed")
        }
        #expect(T.map(URLError(.notConnectedToInternet), during: .download).isModelUnavailable)
    }

    @Test func vadUsesTheSDKThreshold() {
        #expect(ArgmaxTranscriber.silenceThreshold(.voiceTriggered(silenceThreshold: 0.42)) == 0.42)
        #expect(ArgmaxTranscriber.silenceThreshold(.alwaysOn) == StreamTranscriptionMode.defaultSilenceThreshold)
    }

    @Test func customVocabularyIsNotClaimed() {
        #expect(ArgmaxTranscriber(settings: ArgmaxSettings(apiKey: nil)).capabilities.customVocabulary == false)
    }

    @Test func fileFeederAppendsSilenceAndFinishes() async throws {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Float].self, throwing: (any Error).self)
        await ArgmaxTranscriber.feed([Float](repeating: 0.5, count: 2_000), trailingSilence: 0.25, realtime: false, into: continuation)
        var total = 0
        for try await chunk in stream { total += chunk.count }
        #expect(total == 2_000 + 4_000)
    }
}

private extension AudioError {
    var isModelUnavailable: Bool { if case .modelUnavailable = self { true } else { false } }
}

// MARK: - Live (requires ARGMAX_API_KEY, network on first run, and `say`)

/// Synthesizes a spoken fixture with macOS `say` into a temp file (never committed).
func synthesize(_ text: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID().uuidString).aiff")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-o", url.path, text]
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw AudioError.engineFailed("say failed") }
    return url
}

@Suite(
    "Live Argmax transcription",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_ARGMAX"] == "1"),
    .serialized
)
struct LiveArgmaxTests {
    /// Speech followed by 6 s of silence *inside* the audio: the utterance must be
    /// finalized from confirmed text shortly after speech ends, not when input closes.
    @Test func synthesizedOpenNotesFinalizesDuringSilence() async throws {
        let audio = try synthesize("Open Notes. [[slnc 6000]]")
        defer { try? FileManager.default.removeItem(at: audio) }
        let transcriber = ArgmaxTranscriber(
            settings: .fromEnvironment(input: .file(audio, realtime: true, trailingSilence: 1)))
        try await transcriber.prepare()
        let d = await transcriber.diagnostics
        print("LIVE argmax sdk=\(d.sdkVersion) download=\(String(describing: d.downloadDuration)) load=\(String(describing: d.loadDuration)) license=\(d.lastLicenseEvent ?? "-")")

        var assembler = UtteranceAssembler()
        var finals: [(String, TimeInterval)] = []
        var speechEndedAt: TimeInterval?
        let clock = ContinuousClock()
        let t0 = clock.now
        func seconds() -> TimeInterval {
            let c = (clock.now - t0).components
            return Double(c.seconds) + Double(c.attoseconds) / 1e18
        }
        for try await event in try await transcriber.start() {
            let now = seconds()
            print("LIVE event @\(String(format: "%.2f", now))s: \(event)")
            if event == .voiceActivity(.speechEnded), speechEndedAt == nil { speechEndedAt = now }
            for case .final(let text, _) in assembler.ingest(event, at: now) { finals.append((text, now)) }
        }
        for case .final(let text, _) in assembler.finish() { finals.append((text, seconds())) }
        print("LIVE finals=\(finals) speechEnded=\(String(describing: speechEndedAt)) elapsed=\(seconds())s")

        let first = try #require(finals.first)
        #expect(first.0.lowercased().contains("open"))
        #expect(first.0.lowercased().contains("notes"))
        let ended = try #require(speechEndedAt)
        #expect(first.1 - ended < 2.5, "final should follow end of speech, not end of input")
        #expect(first.1 < seconds() - 3, "final must arrive while silence is still streaming")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_LLM"] == "1"))
    func openNotesMilestoneEndToEnd() async throws {
        let audio = try synthesize("Open Notes. [[slnc 4000]]")
        defer { try? FileManager.default.removeItem(at: audio) }
        let sink = MockActionConsumer()
        let pipeline = VoicePipeline(
            transcriber: ArgmaxTranscriber(settings: .fromEnvironment(input: .file(audio, realtime: true, trailingSilence: 3))),
            permission: nil,
            classifier: BonsaiIntentClassifier(client: LMStudioClient(configuration: try LMStudioConfiguration())),
            sink: sink)
        try await pipeline.run()
        let received = await sink.received
        for r in received { print("LIVE e2e “\(r.utterance.stableText)” -> \(r.outcome) in \(r.routingLatency)") }
        #expect(await sink.actions == [.activateApp(.notes)])
    }
}
