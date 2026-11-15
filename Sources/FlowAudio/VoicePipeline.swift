import FlowCore
import Foundation

/// Listening status for the HUD (spec 02 §3 `WAKE_IDLE`/`LISTENING`/`ROUTING` subset
/// owned by the audio layer).
public enum ListeningState: Sendable, Equatable {
    case idle
    case checkingPermission
    case preparing
    case listening
    case hearing(PartialTranscript)
    case routing(String)
    case stopped
    case failed(AudioError)
}

/// How an utterance was interpreted.
public enum RouteSource: Sendable, Equatable {
    /// Reserved control phrase matched by code; no model call was made.
    case deterministic
    /// Interpreted by the language-model classifier and validated.
    case model
}

/// A finalized utterance plus its validated interpretation (or typed failure).
public struct RoutedUtterance: Sendable, Equatable {
    public let utterance: Utterance
    public let outcome: Result<Intent, ClassificationError>
    public let routedBy: RouteSource
    /// From finalized utterance to validated intent.
    public let routingLatency: Duration

    public init(
        utterance: Utterance, outcome: Result<Intent, ClassificationError>, routedBy: RouteSource,
        routingLatency: Duration
    ) {
        self.utterance = utterance
        self.outcome = outcome
        self.routedBy = routedBy
        self.routingLatency = routingLatency
    }

    public var intent: Intent? { try? outcome.get() }
}

/// Receives validated intents. This is the boundary to the planner/executor (Track A);
/// implementations decide what to do. Nothing in FlowAudio executes actions.
public protocol IntentSink: Sendable {
    func deliver(_ routed: RoutedUtterance) async
}

public enum PipelineEvent: Sendable, Equatable {
    case state(ListeningState)
    /// Interim text for display only.
    case partial(PartialTranscript)
    /// Speech ended without stable text; nothing was routed.
    case incomplete(PartialTranscript)
    case finalized(Utterance)
    case routed(RoutedUtterance)
}

/// Microphone → stable utterances → deterministic control phrases → model classifier → sink.
///
/// Invariants (spec 02 §3):
/// - Only finalized, ASR-confirmed text is routed; hypotheses never are.
/// - `stop`/`cancel` are recognized by code without the model and cancel any in-flight
///   classification (STOP has priority over LLM calls).
/// - Commands are classified one at a time, in spoken order.
public actor VoicePipeline {
    public nonisolated let events: AsyncStream<PipelineEvent>
    public nonisolated let sessionID: UUID
    public private(set) var state: ListeningState = .idle

    private let eventsContinuation: AsyncStream<PipelineEvent>.Continuation
    private let transcriber: any SpeechTranscribing
    private let permission: (any MicrophonePermissionProviding)?
    private let classifier: any IntentClassifying
    private let sink: any IntentSink
    private let tickInterval: Duration
    private let onControl: (@Sendable (ControlCommand) async -> Void)?
    private let now: @Sendable () -> TimeInterval
    private var assembler: UtteranceAssembler
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var tail: Task<Void, Never>?

    /// - Parameters:
    ///   - permission: microphone consent provider; pass `nil` only when the transcriber
    ///     reads a file or synthetic input rather than a microphone.
    ///   - onControl: called for every control phrase (after pending commands are cancelled).
    public init(
        transcriber: any SpeechTranscribing,
        permission: (any MicrophonePermissionProviding)?,
        classifier: any IntentClassifying,
        sink: any IntentSink,
        policy: EndpointPolicy = EndpointPolicy(),
        sessionID: UUID = UUID(),
        tickInterval: Duration = .milliseconds(50),
        onControl: (@Sendable (ControlCommand) async -> Void)? = nil,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.transcriber = transcriber
        self.permission = permission
        self.classifier = classifier
        self.sink = sink
        self.assembler = UtteranceAssembler(policy: policy)
        self.sessionID = sessionID
        self.tickInterval = tickInterval
        self.onControl = onControl
        self.now = now
        (events, eventsContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Runs until `stop()` is called or the input ends. All in-flight routing completes
    /// before this returns.
    public func run() async throws(AudioError) {
        switch state {
        case .idle, .stopped, .failed: break
        default: throw .alreadyRunning
        }
        assembler.reset()

        let stream: AsyncThrowingStream<TranscriptEvent, any Error>
        do {
            if let permission {
                set(.checkingPermission)
                try await MicrophoneGate.ensureAccess(permission)
            }
            set(.preparing)
            try await transcriber.prepare()
            stream = try await transcriber.start()
        } catch {
            set(.failed(error))
            throw error
        }
        set(.listening)

        let ticker = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                await self?.tick()
            }
        }
        defer { ticker.cancel() }

        do {
            for try await event in stream {
                await handle(assembler.ingest(event, at: now()))
            }
            await handle(assembler.finish())
            await drainInFlight()
            set(.stopped)
        } catch {
            ticker.cancel()
            await handle(assembler.finish())
            await drainInFlight()
            let failure: AudioError =
                error is CancellationError ? .cancelled : (error as? AudioError ?? .engineFailed(String(describing: error)))
            set(.failed(failure))
            throw failure
        }
    }

    /// Stops capture. The current stable text (if complete) is still finalized and routed.
    public func stop() async {
        await transcriber.stop()
    }

    /// Cancels classification that has not yet been delivered. Already-delivered intents
    /// are unaffected (cancellation cannot reverse committed effects).
    public func cancelPendingCommands() {
        for task in inFlight.values { task.cancel() }
    }

    // MARK: - Internals

    private func tick() async {
        await handle(assembler.tick(at: now()))
    }

    private func handle(_ outputs: [AssemblerOutput]) async {
        for output in outputs {
            switch output {
            case .partial(let partial):
                emit(.partial(partial))
                set(.hearing(partial))
            case .incomplete(let partial):
                emit(.incomplete(partial))
                set(inFlight.isEmpty ? .listening : state)
            case .final(let text, let language):
                let utterance = Utterance(stableText: text, language: language, sessionID: sessionID)
                emit(.finalized(utterance))
                await route(utterance)
            }
        }
    }

    private func route(_ utterance: Utterance) async {
        let started = ContinuousClock.now

        if let control = DeterministicRouter.route(utterance.stableText) {
            if control.control == .stop || control.control == .cancel {
                cancelPendingCommands()
            }
            // Lets stateful classifiers (e.g. the intent router) drop open questions.
            if let command = control.control { await onControl?(command) }
            let routed = RoutedUtterance(
                utterance: utterance, outcome: .success(control), routedBy: .deterministic,
                routingLatency: ContinuousClock.now - started)
            // Delivered immediately, ahead of queued commands.
            await sink.deliver(routed)
            emit(.routed(routed))
            set(inFlight.isEmpty ? .listening : state)
            return
        }

        set(.routing(utterance.stableText))
        let previous = tail
        let classifier = self.classifier
        let task = Task { [weak self] in
            await previous?.value
            var outcome: Result<Intent, ClassificationError> = .failure(.cancelled)
            if !Task.isCancelled {
                do throws(ClassificationError) {
                    outcome = .success(try await classifier.classify(utterance.stableText))
                } catch {
                    outcome = .failure(error)
                }
            }
            // A stop that arrived while the model was answering wins over its result.
            if Task.isCancelled { outcome = .failure(.cancelled) }
            let routed = RoutedUtterance(
                utterance: utterance, outcome: outcome,
                // A classifier may answer deterministically (fast path, context, clarification).
                routedBy: (try? outcome.get())?.source == .deterministic ? .deterministic : .model,
                routingLatency: ContinuousClock.now - started)
            await self?.finish(routed)
        }
        inFlight[utterance.id] = task
        tail = task
    }

    private func finish(_ routed: RoutedUtterance) async {
        inFlight[routed.utterance.id] = nil
        await sink.deliver(routed)
        emit(.routed(routed))
        if inFlight.isEmpty, case .routing = state { set(.listening) }
    }

    private func drainInFlight() async {
        while let task = tail {
            await task.value
            if tail == task { tail = nil }
        }
    }

    private func set(_ new: ListeningState) {
        guard new != state else { return }
        state = new
        emit(.state(new))
    }

    private func emit(_ event: PipelineEvent) {
        eventsContinuation.yield(event)
    }
}

/// Records delivered intents for tests and the developer harness. Executes nothing.
public actor MockActionConsumer: IntentSink {
    public private(set) var received: [RoutedUtterance] = []
    private let onDeliver: (@Sendable (RoutedUtterance) -> Void)?

    public init(onDeliver: (@Sendable (RoutedUtterance) -> Void)? = nil) {
        self.onDeliver = onDeliver
    }

    public func deliver(_ routed: RoutedUtterance) {
        received.append(routed)
        onDeliver?(routed)
    }

    public var actions: [FlowAction] { received.compactMap { $0.intent?.action } }
}
