import FlowCore
import FlowPlanner
import FlowSession
import Foundation

/// Spoken-feedback state for the HUD.
public enum FeedbackStatus: Sendable, Equatable {
    case ready
    case speaking(String)
    /// No usable voice: feedback is visual only.
    case unavailable(String)
    case muted
}

public enum FeedbackEvent: Sendable, Equatable {
    case status(FeedbackStatus)
    case spoke(SpeechCue)
    case interrupted(SpeechCue)
    /// Not spoken because speech is unavailable or muted (still shown visually).
    case skipped(SpeechCue)
    /// A finalized utterance was dropped by the echo guard.
    case ignored(utterance: String, reason: EchoGuard.Reason)
    /// The listening session or a pending question timed out.
    case timedOut(String)
}

/// Timings for reminders and timeouts (spec 02 §11 inactivity timeout; PRD D-008).
public struct FeedbackTiming: Sendable, Equatable {
    /// Unanswered question → one spoken reminder.
    public var reminderAfter: Duration
    /// Unanswered send confirmation → cancelled (never sent). Measured from the question.
    public var confirmationTimeout: Duration
    /// Listening with nothing to do and no speech → listening stops.
    public var idleListeningTimeout: Duration

    public init(reminderAfter: Duration = .seconds(20), confirmationTimeout: Duration = .seconds(45),
                idleListeningTimeout: Duration = .seconds(300)) {
        self.reminderAfter = reminderAfter
        self.confirmationTimeout = confirmationTimeout
        self.idleListeningTimeout = idleListeningTimeout
    }
}

/// Speaks Flow's important feedback during a voice session, without changing how the
/// session routes, plans or executes (docs/adr/0008-spoken-feedback.md).
///
/// Attach with `attach(to:)`. It installs itself as the coordinator's `VoiceSessionHook`:
/// - `admit`: drops Flow's own speech picked up by the microphone (`EchoGuard`); a
///   stop/cancel stops speech immediately and is still handled by the session.
/// - `observe`: turns and status changes → `FeedbackPolicy` → `SpeechOutput`.
/// It acts on the session only through the coordinator's public API (`submit("cancel")`
/// for an expired confirmation, `stopListening()` for an idle session).
public actor SpokenFeedback: VoiceSessionHook {
    public nonisolated let events: AsyncStream<FeedbackEvent>
    public private(set) var status: FeedbackStatus = .ready
    public private(set) var spoken: [SpeechCue] = []
    public var policy: FeedbackPolicy
    public let timing: FeedbackTiming

    private let output: any SpeechOutput
    private let eventsContinuation: AsyncStream<FeedbackEvent>.Continuation
    private let inbox: AsyncStream<CoordinatorEvent>
    private let inboxContinuation: AsyncStream<CoordinatorEvent>.Continuation
    private var guardState = EchoGuard()
    private weak var coordinator: VoiceSessionCoordinator?
    private var inboxTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var current: SpeechCue?
    private var available = true
    private var muted = false

    // Turn → status pairing: the coordinator emits a turn, then the task phase it led to.
    private var pendingTurn: SessionTurn?
    private var lastListen: ListenStatus = .off
    private var lastPhase: TaskPhase = .idle
    private var lastQuestion: SpeechCue?
    private var phaseTimer: Task<Void, Never>?
    private var idleTimer: Task<Void, Never>?
    private var autoCancelling = false

    public init(output: any SpeechOutput, policy: FeedbackPolicy = FeedbackPolicy(), timing: FeedbackTiming = FeedbackTiming(),
                echoGuard: EchoGuard = EchoGuard()) {
        self.output = output
        self.policy = policy
        self.timing = timing
        self.guardState = echoGuard
        (events, eventsContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (inbox, inboxContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Checks the voice and installs the hook on `coordinator`.
    public func attach(to coordinator: VoiceSessionCoordinator) async {
        self.coordinator = coordinator
        if case .unavailable(let why) = await output.availability() {
            available = false
            setStatus(.unavailable(why))
        }
        if inboxTask == nil {
            inboxTask = Task { [weak self, inbox] in
                for await event in inbox { await self?.handle(event) }
            }
        }
        await coordinator.setHook(self)
    }

    /// Removes the hook and stops speaking.
    public func detach() async {
        await coordinator?.setHook(nil)
        await stopSpeaking()
        phaseTimer?.cancel()
        idleTimer?.cancel()
        inboxTask?.cancel()
        inboxTask = nil
    }

    public func setMuted(_ on: Bool) async {
        muted = on
        if on { await stopSpeaking() }
        setStatus(on ? .muted : (available ? .ready : status))
    }

    /// Stops the current spoken feedback (e.g. a "Stop speaking" button). Tasks are unaffected.
    public func stopSpeaking() async {
        guard current != nil else { return }
        await output.stop()
    }

    // MARK: VoiceSessionHook

    public func admit(_ utterance: String, heardFrom: Date?, finalizedAt: Date) async -> Bool {
        switch guardState.decide(utterance, heardFrom: heardFrom, finalizedAt: finalizedAt) {
        case .accept:
            restartIdleTimer()
            return true
        case .acceptAndInterrupt:
            await stopSpeaking()
            return true
        case .reject(let reason):
            emit(.ignored(utterance: utterance, reason: reason))
            return false
        }
    }

    public nonisolated func observe(_ event: CoordinatorEvent) {
        inboxContinuation.yield(event)
    }

    // MARK: Event handling

    private func handle(_ event: CoordinatorEvent) async {
        switch event {
        case .turn(let turn):
            if let previous = pendingTurn { await respond(to: previous, phase: lastPhase) }
            pendingTurn = turn
            if EchoGuard.isStopOrCancel(turn.utterance) { await stopSpeaking() }
            restartIdleTimer()
        case .status(let s):
            let listenChanged = s.listen != lastListen
            if listenChanged, let cue = policy.cue(forListenChange: lastListen, s.listen) { say(cue) }
            if listenChanged { lastListen = s.listen; restartIdleTimer() }
            if s.task != lastPhase {
                lastPhase = s.task
                if case .working = s.task {} else if let turn = pendingTurn {
                    pendingTurn = nil
                    await respond(to: turn, phase: s.task)
                }
                restartPhaseTimer(for: s.task)
            }
        case .finalized:
            restartIdleTimer()
        case .incomplete:
            break
        }
    }

    private func respond(to turn: SessionTurn, phase: TaskPhase) async {
        if autoCancelling, EchoGuard.isStopOrCancel(turn.utterance) {
            autoCancelling = false
            say(SpeechCue(.notice, "I didn't hear an answer, so I didn't send it."))
            return
        }
        guard let cue = policy.cue(for: turn, phase: phase) else { return }
        if cue.kind == .question || cue.kind == .confirmation { lastQuestion = cue }
        say(cue)
    }

    // MARK: Speaking

    /// Newer feedback replaces older: the current sentence is cut and the new one spoken.
    private func say(_ cue: SpeechCue) {
        guard available, !muted else {
            spoken.append(cue)
            emit(.skipped(cue))
            return
        }
        let previous = speechTask
        speechTask = Task { [weak self] in
            if let previous {
                await self?.interruptCurrent()
                await previous.value
            }
            await self?.speakNow(cue)
        }
    }

    private func interruptCurrent() async {
        if current != nil { await output.stop() }
    }

    private func speakNow(_ cue: SpeechCue) async {
        current = cue
        spoken.append(cue)
        guardState.speechStarted(cue.text, at: Date())
        setStatus(.speaking(cue.text))
        let outcome = await output.speak(cue.text)
        guardState.speechEnded(at: Date())
        current = nil
        switch outcome {
        case .finished: emit(.spoke(cue))
        case .interrupted: emit(.interrupted(cue))
        case .unavailable(let why):
            available = false
            emit(.skipped(cue))
            setStatus(.unavailable(why))
            return
        }
        setStatus(muted ? .muted : .ready)
    }

    // MARK: Timers

    private func restartPhaseTimer(for phase: TaskPhase) {
        phaseTimer?.cancel()
        switch phase {
        case .awaitingChoice, .awaitingConfirmation, .awaitingAnswer:
            break
        default:
            return
        }
        let reminder = timing.reminderAfter, timeout = timing.confirmationTimeout
        phaseTimer = Task { [weak self] in
            do { try await Task.sleep(for: reminder) } catch { return }
            await self?.remind(phase)
            guard case .awaitingConfirmation = phase else { return }
            do { try await Task.sleep(for: max(.zero, timeout - reminder)) } catch { return }
            await self?.expireConfirmation(phase)
        }
    }

    private func remind(_ phase: TaskPhase) {
        guard phase == lastPhase else { return }
        if case .awaitingChoice = phase, let head = lastQuestion?.text.split(separator: "?").first {
            say(SpeechCue(.reminder, "Still waiting. \(head)?"))
        } else if let cue = policy.reminder(for: phase) {
            say(cue)
        }
    }

    /// An unanswered send confirmation is cancelled, never sent (fails safe).
    private func expireConfirmation(_ phase: TaskPhase) async {
        guard phase == lastPhase, case .awaitingConfirmation = phase, let coordinator else { return }
        autoCancelling = true
        emit(.timedOut("confirmation"))
        await coordinator.submit("cancel")
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        guard let coordinator else { return }
        let timeout = timing.idleListeningTimeout
        idleTimer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.idleExpired(coordinator)
        }
    }

    private func idleExpired(_ coordinator: VoiceSessionCoordinator) async {
        // Never time out while Flow is waiting for an answer: the user may still respond.
        switch lastPhase {
        case .awaitingChoice, .awaitingConfirmation, .awaitingAnswer, .working: return
        default: break
        }
        guard await coordinator.isListening else { return }
        emit(.timedOut("listening"))
        say(SpeechCue(.notice, "I've stopped listening. Start listening again when you need me."))
        await coordinator.stopListening()
    }

    // MARK: Helpers

    private func setStatus(_ s: FeedbackStatus) {
        guard s != status else { return }
        status = s
        emit(.status(s))
    }

    private func emit(_ e: FeedbackEvent) { eventsContinuation.yield(e) }
}
