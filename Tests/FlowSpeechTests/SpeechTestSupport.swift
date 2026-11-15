import FlowAudio
import FlowCore
import FlowLLM
@testable import FlowPlanner
import FlowRouting
@testable import FlowSession
@testable import FlowSpeech
import Foundation
import Synchronization

/// Records what Flow would say; "speaks" for `duration` unless stopped. No audio.
actor RecordingSpeech: SpeechOutput {
    private(set) var said: [String] = []
    private(set) var interrupted: [String] = []
    private let duration: Duration
    private let voice: SpeechAvailability
    private var current: Task<Void, any Error>?

    init(duration: Duration = .milliseconds(30), available: Bool = true) {
        self.duration = duration
        voice = available ? .available(voice: "Test Voice") : .unavailable("No speech voice is installed.")
    }

    func availability() async -> SpeechAvailability { voice }

    func speak(_ text: String) async -> SpeechOutcome {
        if case .unavailable(let why) = voice { return .unavailable(why) }
        said.append(text)
        let duration = self.duration
        let task = Task { try await Task.sleep(for: duration) }
        current = task
        do {
            try await task.value
            current = nil
            return .finished
        } catch {
            current = nil
            interrupted.append(text)
            return .interrupted
        }
    }

    func stop() async { current?.cancel() }
}

/// Model disabled: anything the deterministic router does not handle is declined.
struct SilentModel: TracedIntentClassifying {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))),
                            attempts: [])
    }
}

/// Scripted recognizer: tests push transcript events.
final class ScriptedTranscriber: SpeechTranscribing, Sendable {
    let capabilities = TranscriberCapabilities(interimHypotheses: true, voiceActivityEvents: false, customVocabulary: false)
    private let continuation = Mutex<AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?>(nil)

    func prepare() async throws(AudioError) {}

    func start() async throws(AudioError) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self, throwing: (any Error).self)
        continuation.withLock { $0 = cont }
        return stream
    }

    func stop() async { continuation.withLock { $0?.finish(); $0 = nil } }

    var isStarted: Bool { continuation.withLock { $0 != nil } }

    func say(_ text: String) {
        continuation.withLock { c in
            c?.yield(.hypothesis(text))
            c?.yield(.confirmed(text, language: "en"))
            c?.yield(.endOfSegment)
        }
    }

    /// The microphone/recognizer fails mid-session (e.g. device unplugged).
    func fail(_ error: AudioError) { continuation.withLock { $0?.finish(throwing: error); $0 = nil } }
}

struct FakeMicrophone: MicrophonePermissionProviding {
    func status() -> MicrophoneAuthorization { .authorized }
    func requestAccess() async -> Bool { true }
    func hasInputDevice() -> Bool { true }
}

func twoSarahs() -> MockExecutor.World {
    MockExecutor.World(activeApp: .safari, messages: [
        MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", senderAddress: "sarah.chen@example.invalid",
                   subject: "[FlowTest] Meeting tomorrow", date: "Fri 13 Nov", epoch: 1),
        MessageRef(channel: .mail, id: "m2", sender: "Sarah Okafor", senderAddress: "sarah.okafor@example.invalid",
                   subject: "[FlowTest] Lunch tomorrow?", date: "Thu 12 Nov", epoch: 1),
    ])
}

/// Echo-guard windows scaled to test timings (the defaults are sized for Argmax segmenting).
let testGuard = EchoGuard(tail: 0.15, echoOverlap: 0.6, secondsPerWord: 0.0, endpointDelay: 0.05, partialLatency: 0.05)

/// Coordinator + spoken feedback over the mock executor.
struct SpeechHarness {
    let mock: MockExecutor
    let speech: RecordingSpeech
    let transcriber = ScriptedTranscriber()
    let coordinator: VoiceSessionCoordinator
    let feedback: SpokenFeedback

    init(world: MockExecutor.World = twoSarahs(), speech: RecordingSpeech = RecordingSpeech(),
         timing: FeedbackTiming = FeedbackTiming(), policy: FeedbackPolicy = FeedbackPolicy()) async {
        mock = MockExecutor(world: world)
        self.speech = speech
        let session = TaskSession(store: IntentRouter(model: SilentModel()), executor: mock)
        coordinator = VoiceSessionCoordinator(session: session, transcriber: transcriber, permission: FakeMicrophone(),
                                              policy: EndpointPolicy(trailingSilence: 0.05, unconfirmedTailTimeout: 0.3))
        feedback = SpokenFeedback(output: speech, policy: policy, timing: timing, echoGuard: testGuard)
        await feedback.attach(to: coordinator)
    }

    func listen() async {
        await coordinator.startListening()
        _ = await eventually { transcriber.isStarted }
    }

    var said: [String] { get async { await speech.said } }
    var state: RunState { get async { await coordinator.session.runner.state } }

    /// Waits until Flow has said something matching `predicate`.
    func waitForSpeech(_ predicate: @escaping (String) -> Bool) async -> Bool {
        await eventually { await speech.said.contains(where: predicate) }
    }

    /// Waits until Flow is silent (finished or interrupted) and the echo tail has passed.
    func waitUntilQuiet() async {
        _ = await eventually {
            if case .speaking = await feedback.status { return false }
            return true
        }
        try? await Task.sleep(for: .milliseconds(250))
    }
}

func eventually(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
