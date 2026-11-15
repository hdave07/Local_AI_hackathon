import FlowAudio
import FlowCore
import FlowLLM
import FlowPlanner
import FlowRouting
@testable import FlowSession
import Foundation
import Synchronization

/// Model disabled: anything the deterministic router does not handle is declined.
struct SilentModel: TracedIntentClassifying {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))),
                            attempts: [])
    }
}

/// Scripted recognizer: tests push transcript events; `stop()` ends the stream.
final class ScriptedTranscriber: SpeechTranscribing, Sendable {
    let capabilities = TranscriberCapabilities(interimHypotheses: true, voiceActivityEvents: false, customVocabulary: false)
    private let continuation = Mutex<AsyncThrowingStream<TranscriptEvent, any Error>.Continuation?>(nil)
    private let failPrepare: AudioError?

    init(failPrepare: AudioError? = nil) { self.failPrepare = failPrepare }

    func prepare() async throws(AudioError) {
        if let failPrepare { throw failPrepare }
    }

    func start() async throws(AudioError) -> AsyncThrowingStream<TranscriptEvent, any Error> {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self, throwing: (any Error).self)
        continuation.withLock { $0 = cont }
        return stream
    }

    func stop() async { continuation.withLock { $0?.finish(); $0 = nil } }

    var isStarted: Bool { continuation.withLock { $0 != nil } }

    /// One spoken utterance: optional hypothesis, then confirmed text and end of segment.
    func say(_ text: String) {
        continuation.withLock { c in
            c?.yield(.hypothesis(text))
            c?.yield(.confirmed(text, language: "en"))
            c?.yield(.endOfSegment)
        }
    }

    /// Speech that never becomes stable.
    func mumble(_ text: String) {
        continuation.withLock { c in
            c?.yield(.hypothesis(text))
            c?.yield(.endOfSegment)
        }
    }
}

/// Grants microphone access (or not) without touching the system.
struct FakeMicrophone: MicrophonePermissionProviding {
    var granted = true
    func status() -> MicrophoneAuthorization { granted ? .authorized : .denied }
    func requestAccess() async -> Bool { granted }
    func hasInputDevice() -> Bool { true }
}

func sampleWorld() -> MockExecutor.World {
    MockExecutor.World(activeApp: .safari, messages: [
        MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", senderAddress: "sarah.chen@example.invalid",
                   subject: "[FlowTest] Meeting tomorrow", date: "Fri 13 Nov", epoch: 1),
        MessageRef(channel: .mail, id: "m2", sender: "Sarah Okafor", senderAddress: "sarah.okafor@example.invalid",
                   subject: "[FlowTest] Lunch on Friday?", date: "Thu 12 Nov", epoch: 1),
        MessageRef(channel: .mail, id: "m3", sender: "Priya Patel", senderAddress: "priya.patel@example.invalid",
                   subject: "[FlowTest] Project budget review", date: "Wed 11 Nov", epoch: 1),
    ])
}

/// Waits (bounded) for a condition on an actor-held value.
func eventually(_ timeout: Duration = .seconds(3), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
