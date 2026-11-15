import FlowAudio
import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowMailSend
import FlowPlanner
import FlowRouting
import FlowSession
import FlowSpeech
import Foundation
import Synchronization
import Testing

// Minimal copies of FlowSpeechTests helpers (test targets cannot import each other).
actor SpokenLog: SpeechOutput {
    private(set) var said: [String] = []
    private let duration: Duration
    private var current: Task<Void, any Error>?
    init(duration: Duration = .milliseconds(20)) { self.duration = duration }
    func availability() async -> SpeechAvailability { .available(voice: "Test Voice") }
    func speak(_ text: String) async -> SpeechOutcome {
        said.append(text)
        let d = duration
        let task = Task { try await Task.sleep(for: d) }
        current = task
        do { try await task.value; current = nil; return .finished } catch { current = nil; return .interrupted }
    }
    func stop() async { current?.cancel() }
}

final class Mic: SpeechTranscribing, Sendable {
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
            c?.yield(.hypothesis(text)); c?.yield(.confirmed(text, language: "en")); c?.yield(.endOfSegment)
        }
    }
    func fail(_ error: AudioError) { continuation.withLock { $0?.finish(throwing: error); $0 = nil } }
}

struct AllowedMic: MicrophonePermissionProviding {
    func status() -> MicrophoneAuthorization { .authorized }
    func requestAccess() async -> Bool { true }
    func hasInputDevice() -> Bool { true }
}

@MainActor func soon(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

/// T-023C over the voice path: microphone → router → planner → real executor → MailSender,
/// with spoken feedback. Simulated Mail; nothing is sent.
@MainActor
@Suite("Confirmed sending by voice", .serialized)
struct VoiceSendTests {
    @MainActor
    struct Harness {
        let rig: Rig
        let mic = Mic()
        let speech: SpokenLog
        let coordinator: VoiceSessionCoordinator
        let feedback: SpokenFeedback

        init(_ mode: MailSendMode, speakFor: Duration = .milliseconds(20), timing: FeedbackTiming = FeedbackTiming()) async {
            rig = Rig(drafting: true, sending: mode)
            speech = SpokenLog(duration: speakFor)
            let session = TaskSession(store: IntentRouter(model: ConfirmedSendTests.Model()), executor: rig.executor)
            coordinator = VoiceSessionCoordinator(session: session, transcriber: mic, permission: AllowedMic(),
                                                  policy: EndpointPolicy(trailingSilence: 0.05, unconfirmedTailTimeout: 0.3))
            feedback = SpokenFeedback(output: speech, timing: timing,
                                      echoGuard: EchoGuard(tail: 0.15, echoOverlap: 0.6, secondsPerWord: 0.0, endpointDelay: 0.05,
                                                           partialLatency: 0.05))
            await feedback.attach(to: coordinator)
        }

        func listen() async {
            await coordinator.startListening()
            _ = await soon { mic.isStarted }
        }

        /// Speak, then wait for Flow to finish speaking its answer.
        func say(_ text: String, expecting predicate: @escaping (String) -> Bool) async -> Bool {
            mic.say(text)
            return await soon { await speech.said.contains(where: predicate) }
        }

        func quiet() async {
            _ = await soon { if case .speaking = await feedback.status { return false }; return true }
            try? await Task.sleep(for: .milliseconds(250))
        }

        /// Spoken: find, choose, reply, send → Flow reads the confirmation aloud.
        func reachConfirmation() async -> Bool {
            guard await say("Find Sarah's email.", expecting: { $0.contains("Which") }) else { return false }
            await quiet()
            mic.say("The first one.")
            let chosen = await soon { await coordinator.session.store.context.selectedMessage != nil }
            guard chosen else { return false }
            await quiet()
            mic.say("Reply saying I can meet at 3:30.")
            let drafted = await soon { rig.draftBackend.open.count == 1 }
            guard drafted else { return false }
            await quiet()
            return await say("Send that reply.", expecting: { $0.hasPrefix("Send this email to sarah.chen@example.invalid?") && $0.contains("I can meet at 3:30") })
        }
    }

    @Test func spokenYesInDryRunRecordsOneAttemptAndAnnouncesIt() async {
        let h = await Harness(.dryRun)
        await h.listen()
        #expect(await h.reachConfirmation())
        await h.quiet()
        #expect(await h.say("Yes, send it.", expecting: { $0.contains("Dry run") && $0.contains("Nothing was sent") }))
        #expect(h.rig.sender?.dryRunLog.count == 1)
        #expect(h.rig.sendTransport.sendCalls == 0)
    }

    @Test func repeatedSpeechNeverSendsTwice() async {
        let h = await Harness(.live)
        await h.listen()
        #expect(await h.reachConfirmation())
        await h.quiet()
        #expect(await h.say("Yes, send it.", expecting: { $0.contains("Sent mailbox") }))
        await h.quiet()
        h.mic.say("Yes, send it.")  // the recognizer repeats the segment
        h.mic.say("Send that reply.")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(h.rig.sendTransport.sendCalls == 1)
    }

    @Test func flowsOwnConfirmationHeardWhileSpeakingIsNotApproval() async {
        let h = await Harness(.live, speakFor: .milliseconds(600))
        await h.listen()
        #expect(await h.reachConfirmation())
        // While Flow is still reading the confirmation, the microphone picks it up.
        let prompt = await h.speech.said.last!
        h.mic.say(prompt)
        h.mic.say("yes")  // half-duplex: speech during Flow's sentence is dropped
        try? await Task.sleep(for: .milliseconds(800))
        #expect(h.rig.sendTransport.sendCalls == 0)
    }

    @Test func unansweredConfirmationTimesOutAndNeverSends() async {
        let h = await Harness(.live, timing: FeedbackTiming(reminderAfter: .milliseconds(150), confirmationTimeout: .milliseconds(400),
                                                             idleListeningTimeout: .seconds(60)))
        await h.listen()
        #expect(await h.reachConfirmation())
        #expect(await soon { await h.speech.said.contains("I didn't hear an answer, so I didn't send it.") })
        await h.quiet()
        h.mic.say("yes")
        try? await Task.sleep(for: .milliseconds(500))
        #expect(h.rig.sendTransport.sendCalls == 0)
    }

    @Test func microphoneFailureDuringConfirmationSendsNothing() async {
        let h = await Harness(.live)
        await h.listen()
        #expect(await h.reachConfirmation())
        h.mic.fail(.engineFailed("device disconnected"))
        #expect(await soon { await h.speech.said.contains { $0.hasPrefix("I stopped listening.") } })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(h.rig.sendTransport.sendCalls == 0)
    }

    @Test func spokenNeverMindCancelsAndSaysSo() async {
        let h = await Harness(.live)
        await h.listen()
        #expect(await h.reachConfirmation())
        await h.quiet()
        #expect(await h.say("Actually, never mind.", expecting: { $0.contains("won't send") }))
        #expect(h.rig.sendTransport.sendCalls == 0)
    }

    @Test func unknownOutcomeIsAnnouncedAsUncertain() async {
        let h = await Harness(.live)
        await h.listen()
        #expect(await h.reachConfirmation())
        await h.quiet()
        h.rig.sendTransport.behavior = .throwsAfterSend
        #expect(await h.say("Yes, send it.", expecting: { $0.contains("couldn't confirm") }))
        #expect(!(await h.speech.said).contains { $0.contains("Sent mailbox") })
    }
}
