import FlowAudio
import FlowCore
import FlowPlanner
import FlowRouting
import Foundation

/// Microphone/recognizer status for the HUD.
public enum ListenStatus: Sendable, Equatable {
    case off
    case starting
    case listening
    /// Interim words, display only (never routed).
    case hearing(String)
    case failed(String)
}

/// Task status for the HUD, derived from `TaskSession` replies and `RunState`.
public enum TaskPhase: Sendable, Equatable {
    case idle
    case working(String)
    case awaitingChoice(prompt: String, options: [String])
    case awaitingConfirmation(String)
    /// The router asked a question (e.g. "Which app?"); the next utterance answers it.
    case awaitingAnswer(String)
    case finished(String)
}

public struct CoordinatorStatus: Sendable, Equatable {
    public var listen: ListenStatus = .off
    public var task: TaskPhase = .idle

    public init(listen: ListenStatus = .off, task: TaskPhase = .idle) {
        self.listen = listen
        self.task = task
    }
}

public enum TurnSource: String, Sendable, Equatable {
    case voice
    case typed
}

/// One utterance and what Flow did with it (evidence; contains no message bodies).
public struct SessionTurn: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let utterance: String
    public let source: TurnSource
    public let say: [String]
    public let state: RunState
    public let planSummary: String?
    public let runEvents: [RunEvent]
    /// From finalized utterance (or typed submission) to the end of handling.
    public let duration: Duration
}

public enum CoordinatorEvent: Sendable, Equatable {
    case status(CoordinatorStatus)
    /// A finalized utterance from the recognizer (before handling).
    case finalized(String)
    /// Speech ended without stable text; nothing was handled.
    case incomplete(String)
    case turn(SessionTurn)
}

/// Optional extension point for components layered on the voice session (e.g. spoken
/// feedback, docs/adr/0008-spoken-feedback.md). Without a hook the coordinator behaves
/// exactly as before.
public protocol VoiceSessionHook: AnyObject, Sendable {
    /// Called for every finalized *spoken* utterance before it is handled (typed input is
    /// never gated). Return false to drop it, e.g. because it is Flow's own speech picked up
    /// by the microphone. stop/cancel decisions stay with the hook; a dropped utterance runs nothing.
    func admit(_ utterance: String, heardFrom: Date?, finalizedAt: Date) async -> Bool
    /// Every coordinator event, in order. Must return quickly (do not block the coordinator).
    func observe(_ event: CoordinatorEvent)
}

/// Voice-session coordinator: the glue between `VoicePipeline` (Argmax → finalized
/// utterances) and `TaskSession` (FlowRouting context + FlowPlanner run state → executor).
///
/// Design (docs/adr/0007-voice-session-coordinator.md):
/// - **Routing happens once**, in `TaskSession`. The pipeline gets a pass-through
///   classifier, so the router's context is never mutated twice for one utterance.
/// - **No state of its own** beyond the HUD status and a turn log: task state stays in the
///   router's `ConversationContext` and the planner's `PlanRunner`.
/// - Commands are handled **one at a time, in spoken order**. stop/cancel bypass the queue,
///   cancel the in-flight step at the executor's next checkpoint, and drop queued commands.
/// - Only finalized utterances are handled; interim text is display-only.
public actor VoiceSessionCoordinator: IntentSink {
    public nonisolated let events: AsyncStream<CoordinatorEvent>
    public let session: TaskSession
    public private(set) var status = CoordinatorStatus()
    public private(set) var turns: [SessionTurn] = []

    private let continuation: AsyncStream<CoordinatorEvent>.Continuation
    private var transcriber: (any SpeechTranscribing)?
    private let permission: (any MicrophonePermissionProviding)?
    private let policy: EndpointPolicy
    private var pipeline: VoicePipeline?
    private var runTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?
    private var tail: Task<Void, Never>?
    /// Incremented by stop/cancel; queued commands from an older generation are dropped.
    private var generation = 0
    private var pending = 0
    private var hook: (any VoiceSessionHook)?
    /// When the recognizer first reported speech for the utterance being heard.
    private var heardFrom: Date?

    public init(session: TaskSession, transcriber: (any SpeechTranscribing)?, permission: (any MicrophonePermissionProviding)?,
                policy: EndpointPolicy = EndpointPolicy()) {
        self.session = session
        self.transcriber = transcriber
        self.permission = permission
        self.policy = policy
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public var isListening: Bool { runTask != nil }

    /// Installs (or removes) the session hook. See `VoiceSessionHook`.
    public func setHook(_ hook: (any VoiceSessionHook)?) {
        self.hook = hook
    }

    /// Installs a recognizer (e.g. once its license key is available). Ignored while listening.
    public func setTranscriber(_ transcriber: (any SpeechTranscribing)?) {
        guard runTask == nil else { return }
        self.transcriber = transcriber
    }

    // MARK: Listening

    /// Starts the microphone pipeline. Returns immediately; status updates arrive on `events`.
    public func startListening() async {
        guard runTask == nil else { return }
        guard let transcriber else {
            setListen(.failed("No speech recognizer is configured."))
            return
        }
        let store = await session.store
        let pipeline = VoicePipeline(
            transcriber: transcriber, permission: permission, classifier: PassThroughClassifier(), sink: self,
            policy: policy, onControl: { command in
                if command == .stop || command == .cancel { await store.cancelPendingQuestion() }
            })
        self.pipeline = pipeline
        setListen(.starting)
        forwardTask = Task { [weak self] in
            for await event in pipeline.events { await self?.forward(event) }
        }
        runTask = Task { [weak self] in
            do throws(AudioError) {
                try await pipeline.run()
                await self?.pipelineEnded(nil)
            } catch {
                await self?.pipelineEnded(error)
            }
        }
    }

    /// Stops capture. A complete stable utterance in progress is still handled.
    public func stopListening() async {
        await pipeline?.stop()
        await runTask?.value
    }

    private func pipelineEnded(_ error: AudioError?) {
        runTask = nil
        pipeline = nil
        if let error, error != .cancelled {
            setListen(.failed(error.userMessage))
        } else {
            setListen(.off)
        }
    }

    private func forward(_ event: PipelineEvent) {
        switch event {
        case .state(let s):
            switch s {
            case .checkingPermission, .preparing: setListen(.starting)
            case .listening, .routing: setListen(.listening)
            case .hearing(let partial):
                if heardFrom == nil { heardFrom = Date() }
                setListen(.hearing(partial.displayText))
            case .idle, .stopped: break  // reported when the run ends
            case .failed(let error): setListen(.failed(error.userMessage))
            }
        case .partial(let partial):
            if heardFrom == nil { heardFrom = Date() }
            setListen(.hearing(partial.displayText))
        case .incomplete(let partial):
            heardFrom = nil
            emit(.incomplete(partial.displayText))
            if case .hearing = status.listen { setListen(.listening) }
        case .finalized(let utterance):
            emit(.finalized(utterance.stableText))
        case .routed:
            break  // routing is done by TaskSession, not the pipeline (see PassThroughClassifier)
        }
    }

    // MARK: IntentSink (finalized utterances from the pipeline)

    public func deliver(_ routed: RoutedUtterance) async {
        let text = routed.utterance.stableText
        let started = heardFrom
        heardFrom = nil
        if let hook, await !hook.admit(text, heardFrom: started, finalizedAt: Date()) { return }
        if Self.isStopOrCancel(text) {
            await interrupt(text, source: .voice)
        } else {
            enqueue(text, source: .voice)
        }
    }

    // MARK: Typed input (same path, without speech)

    /// Handles typed text exactly like a finalized utterance and waits for its turn.
    @discardableResult
    public func submit(_ text: String) async -> SessionTurn? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if Self.isStopOrCancel(trimmed) { return await interrupt(trimmed, source: .typed) }
        let task = enqueue(trimmed, source: .typed)
        return await task.value
    }

    // MARK: Command queue

    @discardableResult
    private func enqueue(_ text: String, source: TurnSource) -> Task<SessionTurn?, Never> {
        let previous = tail
        let myGeneration = generation
        pending += 1
        let task = Task<SessionTurn?, Never> { [weak self] in
            await previous?.value
            return await self?.runQueued(text, source: source, generation: myGeneration)
        }
        tail = Task { _ = await task.value }
        return task
    }

    private func runQueued(_ text: String, source: TurnSource, generation queuedIn: Int) async -> SessionTurn? {
        pending -= 1
        // A stop/cancel after this command was queued drops it unexecuted.
        guard queuedIn == generation else { return nil }
        return await handle(text, source: source)
    }

    /// stop/cancel: never queued behind other commands (spec 02 §3 priority).
    @discardableResult
    private func interrupt(_ text: String, source: TurnSource) async -> SessionTurn {
        generation += 1
        return await handle(text, source: source)
    }

    private func handle(_ text: String, source: TurnSource) async -> SessionTurn {
        setTask(.working(text))
        let clock = ContinuousClock()
        let started = clock.now
        let reply = await session.handle(text)
        let events = await session.runner.events
        let turn = SessionTurn(id: UUID(), utterance: text, source: source, say: reply.say, state: reply.state,
                               planSummary: reply.plan?.summary, runEvents: reply.plan == nil ? [] : events,
                               duration: clock.now - started)
        turns.append(turn)
        if turns.count > 100 { turns.removeFirst() }
        emit(.turn(turn))
        // A router question lives in the shared context (single store), not in the coordinator.
        var routerQuestion = false
        if let pending = await session.store.context.pending {
            if case .plan = pending {} else { routerQuestion = true }
        }
        setTask(Self.phase(for: reply, routerQuestion: routerQuestion))
        return turn
    }

    static func phase(for reply: SessionReply, routerQuestion: Bool = false) -> TaskPhase {
        switch reply.state {
        case .awaitingChoice(let q): return .awaitingChoice(prompt: q.prompt, options: q.options)
        case .awaitingConfirmation(let r): return .awaitingConfirmation(r.prompt)
        default:
            let said = reply.say.joined(separator: " ")
            return routerQuestion ? .awaitingAnswer(said) : .finished(said)
        }
    }

    static func isStopOrCancel(_ text: String) -> Bool {
        guard let c = DeterministicRouter.route(text)?.control else { return false }
        return c == .stop || c == .cancel
    }

    // MARK: Status

    private func setListen(_ listen: ListenStatus) {
        guard status.listen != listen else { return }
        status.listen = listen
        emit(.status(status))
    }

    private func setTask(_ task: TaskPhase) {
        guard status.task != task else { return }
        status.task = task
        emit(.status(status))
    }

    private func emit(_ event: CoordinatorEvent) {
        continuation.yield(event)
        hook?.observe(event)
    }
}

/// Lets `VoicePipeline` deliver finalized utterances without routing them: `TaskSession`
/// routes each utterance exactly once against the shared task context. stop/cancel are
/// still recognized by the pipeline itself (deterministically) before this is called.
struct PassThroughClassifier: IntentClassifying {
    func classify(_ utterance: String) async throws(ClassificationError) -> Intent {
        Intent(kind: .task, summary: "Handled by TaskSession", source: .deterministic)
    }
}
