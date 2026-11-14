import FlowAudio
import FlowCore
import Foundation
import Synchronization

/// Scripted microphone consent.
final class FakePermission: MicrophonePermissionProviding {
    private let state: Mutex<(status: MicrophoneAuthorization, grant: Bool, device: Bool, requests: Int)>

    init(_ status: MicrophoneAuthorization, grantOnRequest: Bool = true, hasDevice: Bool = true) {
        state = Mutex((status, grantOnRequest, hasDevice, 0))
    }

    var requestCount: Int { state.withLock { $0.requests } }

    func status() -> MicrophoneAuthorization { state.withLock { $0.status } }

    func requestAccess() async -> Bool {
        state.withLock {
            $0.requests += 1
            $0.status = $0.grant ? .authorized : .denied
            return $0.grant
        }
    }

    func hasInputDevice() -> Bool { state.withLock { $0.device } }
}

/// One scripted step of a fake recognizer.
enum Step: Sendable {
    case event(TranscriptEvent)
    case pause(Duration)
    case fail(AudioError)
}

/// Replays scripted events, then ends the stream (or keeps it open until `stop()`).
final class FakeTranscriber: SpeechTranscribing {
    let capabilities: TranscriberCapabilities
    private let script: [Step]
    private let prepareError: AudioError?
    private let holdOpen: Bool
    private let calls = Mutex<(prepared: Int, started: Int, stopped: Int)>((0, 0, 0))
    private let continuation = Mutex<AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?>(nil)

    init(_ script: [Step], prepareError: AudioError? = nil, holdOpen: Bool = false, vad: Bool = false) {
        self.script = script
        self.prepareError = prepareError
        self.holdOpen = holdOpen
        capabilities = TranscriberCapabilities(interimHypotheses: true, voiceActivityEvents: vad, customVocabulary: false)
    }

    var prepareCount: Int { calls.withLock { $0.prepared } }
    var startCount: Int { calls.withLock { $0.started } }

    func prepare() async throws(AudioError) {
        calls.withLock { $0.prepared += 1 }
        if let prepareError { throw prepareError }
    }

    func start() async throws(AudioError) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        calls.withLock { $0.started += 1 }
        let (stream, cont) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self, throwing: (any Error).self)
        continuation.withLock { $0 = cont }
        let script = self.script
        let holdOpen = self.holdOpen
        Task {
            for step in script {
                switch step {
                case .event(let e): cont.yield(e)
                case .pause(let d): try? await Task.sleep(for: d)
                case .fail(let error):
                    cont.finish(throwing: error)
                    return
                }
            }
            if !holdOpen { cont.finish() }
        }
        return stream
    }

    func stop() async {
        calls.withLock { $0.stopped += 1 }
        continuation.withLock { $0?.finish() }
    }
}

/// Classifier double: maps utterances to intents, optionally slowly; records calls.
final class FakeClassifier: IntentClassifying {
    private let delay: Duration
    private let ignoresCancellation: Bool
    private let table: [String: Intent]
    private let log = Mutex<[String]>([])

    init(delay: Duration = .zero, ignoresCancellation: Bool = false, _ table: [String: Intent] = [:]) {
        self.delay = delay
        self.ignoresCancellation = ignoresCancellation
        self.table = table
    }

    var calls: [String] { log.withLock { $0 } }

    func classify(_ utterance: String) async throws(ClassificationError) -> Intent {
        log.withLock { $0.append(utterance) }
        if delay > .zero {
            if ignoresCancellation {
                // Like a server response already in flight: finishes despite cancellation.
                let delay = self.delay
                await Task.detached { try? await Task.sleep(for: delay) }.value
            } else {
                do { try await Task.sleep(for: delay) } catch { throw .cancelled }
            }
        }
        let key = utterance.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard let intent = table[key] else { throw .unsupportedAction("unknown") }
        return intent
    }
}

func openNotesIntent() -> Intent {
    Intent(kind: .direct, action: .activateApp(.notes), summary: "Open Notes", source: .model(id: "fake"))
}

/// Fast endpointing so pipeline tests run in milliseconds.
let fastPolicy = EndpointPolicy(trailingSilence: 0.05, unconfirmedTailTimeout: 0.3, maxUtteranceDuration: 5)

func makePipeline(
    _ transcriber: FakeTranscriber,
    permission: FakePermission? = FakePermission(.authorized),
    classifier: FakeClassifier,
    sink: MockActionConsumer = MockActionConsumer(),
    policy: EndpointPolicy = fastPolicy
) -> VoicePipeline {
    VoicePipeline(
        transcriber: transcriber, permission: permission, classifier: classifier, sink: sink, policy: policy,
        tickInterval: .milliseconds(5))
}

/// Collects all pipeline events until the stream is idle after `run()` returns.
actor EventLog {
    private(set) var events: [PipelineEvent] = []
    func append(_ e: PipelineEvent) { events.append(e) }

    var states: [ListeningState] {
        events.compactMap { if case .state(let s) = $0 { s } else { nil } }
    }
}

func record(_ pipeline: VoicePipeline) -> (EventLog, Task<Void, Never>) {
    let log = EventLog()
    let task = Task {
        for await event in pipeline.events { await log.append(event) }
    }
    return (log, task)
}

/// Runs the pipeline, capturing its typed error as a value.
func runCapturing(_ pipeline: VoicePipeline) async -> AudioError? {
    do {
        try await pipeline.run()
        return nil
    } catch {
        return error
    }
}

/// Lets the event-recording task drain.
func settle() async { try? await Task.sleep(for: .milliseconds(30)) }
