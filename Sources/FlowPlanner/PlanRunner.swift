import FlowCore
import FlowRouting
import Foundation

/// Run state (spec 02 §3 EXECUTING / CLARIFYING / CONFIRMING / RECOVERING / INTERRUPTED subset).
public enum RunState: Sendable, Equatable {
    case idle
    case running(planID: UUID, step: Int)
    /// Paused: the user must choose (e.g. which of several matching messages).
    case awaitingChoice(PlanQuestion)
    /// Paused: a consequential step needs explicit approval of exactly this draft.
    case awaitingConfirmation(ApprovalRequest)
    case completed(planID: UUID)
    case stopped(planID: UUID, reason: String)
    case cancelled(planID: UUID?)

    public var isPaused: Bool {
        switch self {
        case .awaitingChoice, .awaitingConfirmation: true
        default: false
        }
    }
}

public struct PlanQuestion: Sendable, Equatable {
    public let stepID: Int
    public let prompt: String
    public let options: [String]
    public let candidates: [MessageRef]
    public let askedAt: Date
}

/// Progress for the HUD and evidence logs.
public enum RunEvent: Sendable, Equatable {
    case started(Plan)
    case stepStarted(stepID: Int, attempt: Int, summary: String)
    case stepCompleted(stepID: Int, summary: String)
    case retrying(stepID: Int, attempt: Int, reason: String)
    case asked(String)
    case confirmationRequested(String)
    case approvalInvalidated(String)
    case stopped(String)
    case cancelled
    case completed
}

/// Executes one plan at a time against a `PlanExecuting` executor.
///
/// Rules: steps run in dependency order, one at a time; each result is verified against the
/// step's expectation before task state is updated; retries are bounded and only for
/// idempotent low-risk steps the executor marks retry-safe; external actions are never
/// retried and are sent at most once per draft; stop/cancel prevents every later step.
public actor PlanRunner {
    public static let maxExecutorCallsPerPlan = 12
    public static let questionLifetime: TimeInterval = 120

    public private(set) var state: RunState = .idle
    public private(set) var events: [RunEvent] = []
    public private(set) var ledger = SendLedger()
    public private(set) var plan: Plan?

    private let executor: any PlanExecuting
    private let store: IntentRouter  // the single task-context store (FlowRouting)
    private let now: @Sendable () -> Date

    private var done: Set<Int> = []
    private var attempts: [Int: Int] = [:]
    private var staleRefreshes: [Int: Int] = [:]
    private var chosen: [Int: MessageRef] = [:]
    private var approval: Approval?
    private var calls = 0
    private var cancelRequested = false
    private var inFlight: Task<ExecutionResult, Never>?
    /// Messages produced since the last `start`/`answer` call.
    private var spoken: [String] = []

    public init(executor: any PlanExecuting, store: IntentRouter, now: @escaping @Sendable () -> Date = Date.init) {
        self.executor = executor
        self.store = store
        self.now = now
    }

    // MARK: - Public API

    /// Starts a plan (replacing any paused one) and runs until it pauses, completes or stops.
    @discardableResult
    public func start(_ plan: Plan) async -> [String] {
        if state.isPaused { spoken.append("Okay, I've dropped the earlier task.") }
        reset(for: plan)
        log(.started(plan))
        await advance()
        return drainSpoken()
    }

    public enum AnswerResult: Sendable, Equatable {
        case handled([String])
        /// The utterance does not answer the open question.
        case notAnAnswer
    }

    /// Answer to an open question or confirmation. Resumes the plan when resolved.
    public func answer(_ utterance: String) async -> AnswerResult {
        switch state {
        case .awaitingChoice(let question):
            if now().timeIntervalSince(question.askedAt) > Self.questionLifetime {
                // The candidates may be stale; search again rather than trust them.
                chosen[question.stepID] = nil
                spoken.append("That list is out of date; let me look again.")
                state = .running(planID: plan!.id, step: question.stepID)
                await advance()
                return .handled(drainSpoken())
            }
            guard let pick = Self.choose(utterance, from: question.candidates) else {
                // "Sarah Chen" when two of three candidates are hers: ask again among just those.
                if let subset = Self.narrow(utterance, from: question.candidates) {
                    let options = subset.enumerated().map { "\($0.offset + 1). \($0.element.spoken)" }
                    let prompt = "\(subset.count) of those match: " + options.joined(separator: "; ") + ". Which one?"
                    state = .awaitingChoice(PlanQuestion(stepID: question.stepID, prompt: prompt, options: options,
                                                         candidates: subset, askedAt: now()))
                    log(.asked(prompt))
                    await setPending(.plan(prompt: prompt, options: options))
                    return .handled([prompt])
                }
                return .notAnAnswer
            }
            chosen[question.stepID] = pick
            await setPending(nil)
            state = .running(planID: plan!.id, step: question.stepID)
            await advance()
            return .handled(drainSpoken())

        case .awaitingConfirmation(let request):
            if now().timeIntervalSince(request.askedAt) > Approval.lifetime {
                invalidateApproval("The confirmation expired.")
                await setPending(nil)
                stop(SendWording.expired)
                return .handled(drainSpoken())
            }
            switch ConfirmationReply.parse(utterance) {
            case .approve:
                let ctx = await store.context
                guard let live = ctx.draft, live.id == request.draft.id, live.version == request.draft.version,
                      live.contentHash == request.draft.contentHash
                else {
                    invalidateApproval("The draft changed after I asked. Review it again before sending.")
                    stop("The draft changed; nothing was sent.")
                    return .handled(drainSpoken())
                }
                approval = Approval(action: request.action, draft: live, issuedAt: now())
                await setPending(nil)
                state = .running(planID: plan!.id, step: request.stepID)
                await advance()
                return .handled(drainSpoken())
            case .decline:
                invalidateApproval("The user declined.")
                await setPending(nil)
                stop(SendWording.declined)
                return .handled(drainSpoken())
            case .readBack:
                log(.confirmationRequested(request.prompt))
                return .handled([request.prompt])
            case .unclear:
                // Vague assent or a repeated "send it": never an approval; keep waiting.
                return .handled([SendWording.reprompt])
            case .unrelated:
                return .notAnAnswer
            }
        default:
            return .notAnAnswer
        }
    }

    /// Abandon a paused plan because the user moved on (e.g. edited the draft instead of
    /// confirming). Approval is discarded.
    public func abandon(_ reason: String) async {
        guard state.isPaused, let plan else { return }
        invalidateApproval(reason)
        state = .stopped(planID: plan.id, reason: reason)
        log(.stopped(reason))
        await setPending(nil)
    }

    /// stop / cancel: interrupts the in-flight step at the executor's next safe checkpoint
    /// and prevents every later step. Already committed effects are not reversed.
    @discardableResult
    public func cancel() async -> [String] {
        cancelRequested = true
        inFlight?.cancel()
        approval = nil
        switch state {
        case .running, .awaitingChoice, .awaitingConfirmation:
            state = .cancelled(planID: plan?.id)
            log(.cancelled)
            spoken.append("Stopped.")
        default:
            break
        }
        await setPending(nil)
        return drainSpoken()
    }

    /// For tests and diagnostics.
    public var currentApproval: Approval? { approval }

    // MARK: - Execution loop

    private func advance() async {
        guard let plan else { return }
        while !cancelRequested {
            guard let step = plan.steps.first(where: { !done.contains($0.id) && Set($0.dependsOn).isSubset(of: done) }) else {
                if done.count == plan.steps.count {
                    state = .completed(planID: plan.id)
                    log(.completed)
                } else {
                    stop("Some steps could not start.")
                }
                return
            }
            state = .running(planID: plan.id, step: step.id)

            let ctx = await store.context
            if let problem = Self.unmet(step, ctx) {
                stop(problem)
                return
            }

            // Consequential steps: at-most-once and explicit, bound approval.
            if step.requiresConfirmation {
                guard let draft = ctx.draft else { stop("There's no draft to send."); return }
                if let refusal = ledger.refusal(for: draft.id) { stop(refusal); return }
                if approval?.authorizes(.send, on: draft, now: now()) != true {
                    approval = nil
                    let ch = step.channel ?? draft.channel
                    let channelName = ch == .mail ? "email" : "message by \(ch.rawValue)"
                    let prompt = SendWording.confirmation(draft, channelName: channelName)
                    state = .awaitingConfirmation(ApprovalRequest(stepID: step.id, action: .send, draft: draft, prompt: prompt,
                                                                  askedAt: now()))
                    log(.confirmationRequested(prompt))
                    spoken.append(prompt)
                    await setPending(.plan(prompt: prompt, options: ["yes", "no"]))
                    return
                }
            }

            guard calls < Self.maxExecutorCallsPerPlan else {
                stop("This is taking too many attempts, so I stopped.")
                return
            }
            let attempt = (attempts[step.id] ?? 0) + 1
            attempts[step.id] = attempt
            calls += 1
            let request = ExecutionRequest(
                planID: plan.id, stepID: step.id, attempt: attempt, action: step.action, channel: step.channel,
                bindings: bindings(for: step, ctx), expectation: step.expectation)
            log(.stepStarted(stepID: step.id, attempt: attempt, summary: step.summary))

            var sendDraftID: String?
            if step.requiresConfirmation, let id = request.bindings.approval?.draftID {
                sendDraftID = id
                ledger.record(id, .inFlight)
                approval = nil  // single use, whatever happens next
            }

            let executor = self.executor
            let task = Task { await executor.execute(request) }
            inFlight = task
            let result = await task.value
            inFlight = nil

            if let id = sendDraftID { recordSend(id, result) }
            if cancelRequested {
                // The step may have committed; record verified effects, run nothing more.
                if result.status == .completed, Self.verify(step, result.observation, request.bindings) {
                    await apply(result.observation)
                }
                return
            }
            guard await handle(step, request, result) else { return }
        }
    }

    /// Returns true to continue with the next step.
    private func handle(_ step: PlanStep, _ request: ExecutionRequest, _ result: ExecutionResult) async -> Bool {
        switch result.status {
        case .completed:
            guard Self.verify(step, result.observation, request.bindings) else {
                stop("I couldn't confirm “\(step.summary)” worked, so I stopped.")
                return false
            }
            await apply(result.observation)
            done.insert(step.id)
            log(.stepCompleted(stepID: step.id, summary: step.summary))
            if case .lookupResult(let answer) = result.observation { spoken.append(answer) }
            if case .availability(let a) = result.observation { spoken.append(a.answer) }
            if case .reviewShown = result.observation { spoken.append("Here's the draft. Say “send it” when you're ready.") }
            if case .sent(_, let queued) = result.observation {
                // Mail accepted it; delivery to the recipient is never claimed.
                spoken.append(queued
                    ? "Mail accepted it, but it's still in the Outbox, so it hasn't gone out yet."
                    : (result.userMessage.isEmpty ? "Mail sent it. It's in your Sent mailbox; I can't confirm delivery." : result.userMessage))
            }
            if case .sendRehearsed = result.observation {
                spoken.append("Dry run: the draft checked out and I would have sent it now. Nothing was sent.")
            }
            return true

        case .needsClarification:
            if case .messageCandidates(let candidates) = result.observation, candidates.count > 1 {
                let options = candidates.enumerated().map { "\($0.offset + 1). \($0.element.spoken)" }
                let prompt = "I found \(candidates.count) messages: " + options.joined(separator: "; ") + ". Which one?"
                state = .awaitingChoice(PlanQuestion(
                    stepID: step.id, prompt: prompt, options: options, candidates: candidates, askedAt: now()))
                attempts[step.id] = (attempts[step.id] ?? 1) - 1  // the choice is not a failed attempt
                log(.asked(prompt))
                spoken.append(prompt)
                await setPending(.plan(prompt: prompt, options: options))
                return false
            }
            stop(result.userMessage.isEmpty ? "I need more detail to do “\(step.summary)”." : result.userMessage)
            return false

        case .failed:
            if result.error == .staleTarget, (staleRefreshes[step.id] ?? 0) < 1, step.capability == .findMessage {
                staleRefreshes[step.id, default: 0] += 1
                chosen[step.id] = nil
                log(.retrying(stepID: step.id, attempt: (attempts[step.id] ?? 0) + 1, reason: "results changed; searching again"))
                return true
            }
            if result.error == .draftChanged || result.error == .approvalInvalid {
                invalidateApproval("The draft changed outside Flow. Review it again before sending.")
                await markDraftUnreviewed()
                stop("The draft changed outside Flow; nothing was sent.")
                return false
            }
            if step.capability == .send, result.error == .notSent {
                stop(result.userMessage.isEmpty ? "Mail didn't send it. The draft is still open." : result.userMessage)
                return false
            }
            if step.capability == .send, let code = result.error, Self.refusedBeforeSending.contains(code) {
                stop(result.userMessage.isEmpty ? "I didn't send it." : result.userMessage + " Nothing was sent.")
                return false
            }
            if step.capability == .send {
                // Anything but an explicit refusal leaves the send outcome unknown.
                stop("I couldn't confirm it was sent. Check the conversation or Sent folder before trying again.")
                return false
            }
            if case .retry(let max) = step.failurePolicy, result.retrySafe, (attempts[step.id] ?? 0) < max {
                log(.retrying(stepID: step.id, attempt: (attempts[step.id] ?? 0) + 1, reason: result.userMessage))
                return true
            }
            stop(result.userMessage.isEmpty ? "“\(step.summary)” failed." : result.userMessage)
            return false

        case .unverified:
            stop(step.capability == .send
                ? "I couldn't confirm it was sent. Check the conversation or Sent folder before trying again."
                : "I couldn't confirm “\(step.summary)” worked, so I stopped.")
            return false

        case .partiallyCompleted:
            stop("“\(step.summary)” only partly worked, so I stopped. \(result.userMessage)")
            return false

        case .unsupported:
            stop(result.userMessage.isEmpty ? "That isn't supported here." : result.userMessage)
            return false

        case .cancelled:
            state = .cancelled(planID: plan?.id)
            log(.cancelled)
            return false
        }
    }

    // MARK: - State

    private func bindings(for step: PlanStep, _ ctx: ConversationContext) -> StepBindings {
        switch step.capability {
        case .findMessage:
            return StepBindings(message: chosen[step.id])
        case .compose:
            return StepBindings(message: step.repliesToSelectedMessage ? ctx.selectedMessage : nil)
        case .editText, .review:
            return StepBindings(draft: ctx.draft)
        case .send:
            return StepBindings(draft: ctx.draft, approval: approval)
        default:
            return StepBindings()
        }
    }

    /// Writes a verified observation into the shared task context.
    private func apply(_ observation: Observation) async {
        var ctx = await store.context
        // A verified calendar answer (or day shown) makes a bare "what about Friday?" a calendar follow-up.
        switch observation {
        case .availability: ctx.calendarTopic = true
        case .uiActed(let label) where label.hasPrefix("Calendar:"): ctx.calendarTopic = true
        default: ctx.calendarTopic = false
        }
        switch observation {
        case .appActive(let app):
            ctx.activeApp = app
        case .window(let w):
            ctx.selectedWindow = w
            if let app = w.app { ctx.activeApp = app }
        case .messageOpened(let m):
            ctx.selectedMessage = m
            ctx.openMessage = m.subject
            ctx.notePerson(m.sender)
        case .draft(let d):
            if let old = ctx.draft, old.contentHash != d.contentHash || old.version != d.version {
                invalidateApproval("The draft changed, so any earlier approval no longer applies.")
            }
            ctx.draft = d
            ctx.hasDraft = true
        case .reviewShown(let d):
            ctx.draft = d
            ctx.hasDraft = true
            ctx.reviewedDraftVersion = d.version
        case .sent:
            ctx.draft = nil
            ctx.hasDraft = false
            ctx.reviewedDraftVersion = nil
        case .none, .uiActed, .scrolled, .lookupResult, .availability, .messageCandidates, .sendRehearsed:
            break
        }
        ctx.updatedAt = now()
        await store.updateContext(ctx)
    }

    private func markDraftUnreviewed() async {
        var ctx = await store.context
        ctx.reviewedDraftVersion = nil
        await store.updateContext(ctx)
    }

    /// Mirrors the plan's open question into the shared context (requirement: task context
    /// holds the pending clarification). Clearing only removes a plan question.
    private func setPending(_ question: PendingQuestion?) async {
        var ctx = await store.context
        if question == nil {
            guard case .plan = ctx.pending else { return }
        }
        ctx.pending = question
        await store.updateContext(ctx)
    }

    /// Executor errors that guarantee nothing was dispatched (ADR 0010).
    static let refusedBeforeSending: Set<ExecutionErrorCode> = [
        .approvalInvalid, .draftChanged, .recipientMismatch, .draftAlreadyOpen, .targetNotFound, .permissionDenied, .appUnavailable,
    ]

    private func recordSend(_ draftID: String, _ result: ExecutionResult) {
        switch result.status {
        case .completed:
            if case .sendRehearsed = result.observation { ledger.record(draftID, .rehearsed) } else { ledger.record(draftID, .sent) }
        case .unsupported:
            ledger.clearInFlight(draftID)  // sending disabled: nothing dispatched
        case .failed where result.error.map { Self.refusedBeforeSending.contains($0) || $0 == .notSent } ?? false:
            ledger.clearInFlight(draftID)  // refused before sending, or Mail reported it did not send
        default:
            ledger.record(draftID, .unverified)  // unknown outcome: never retried automatically
        }
    }

    private func invalidateApproval(_ reason: String) {
        var awaiting = false
        if case .awaitingConfirmation = state { awaiting = true }
        guard approval != nil || awaiting else { return }
        approval = nil
        log(.approvalInvalidated(reason))
    }

    private func reset(for plan: Plan) {
        self.plan = plan
        done = []
        attempts = [:]
        staleRefreshes = [:]
        chosen = [:]
        approval = nil
        calls = 0
        cancelRequested = false
        events = []
    }

    private func stop(_ reason: String) {
        state = .stopped(planID: plan?.id ?? UUID(), reason: reason)
        log(.stopped(reason))
        spoken.append(reason)
    }

    private func log(_ e: RunEvent) { events.append(e) }

    private func drainSpoken() -> [String] {
        defer { spoken = [] }
        return spoken
    }

    // MARK: - Pure checks

    static func unmet(_ step: PlanStep, _ ctx: ConversationContext) -> String? {
        for p in step.preconditions {
            switch p {
            case .messageSelected:
                guard let m = ctx.selectedMessage else { return "Which message should I reply to? Find it first." }
                if let ch = step.channel, m.channel != ch { return "The open message is on \(m.channel), not \(ch)." }
            case .draftExists:
                guard ctx.draft != nil else { return "There's no draft yet." }
            case .draftReviewedCurrentVersion:
                guard ctx.draftReviewed else { return "Review the current draft before sending." }
            }
        }
        if step.capability.isMessaging, step.capability != .findMessage, let ch = step.channel, let d = ctx.draft,
           step.capability != .compose, d.channel != ch
        {
            return "The open draft is on \(d.channel), not \(ch)."
        }
        return nil
    }

    /// Does the observation show the step's expected outcome?
    static func verify(_ step: PlanStep, _ observation: Observation, _ bindings: StepBindings) -> Bool {
        switch (step.expectation, observation) {
        case (.appFrontmost(let app), .appActive(let seen)):
            return app == seen
        case (.windowChanged, .window), (.uiActed, .uiActed), (.scrolled, .scrolled), (.lookupAnswered, .lookupResult),
             (.lookupAnswered, .availability):
            return true
        case (.messageOpened(let query), .messageOpened(let m)):
            if let ch = step.channel, m.channel != ch { return false }
            if let pick = bindings.message { return pick.id == m.id }
            return matches(query: query, m)
        case (.draftWritten(let recipient, let content), .draft(let d)):
            if let ch = step.channel, d.channel != ch { return false }
            if !content.isEmpty, !d.body.contains(content) { return false }  // content preserved verbatim
            if step.repliesToSelectedMessage {
                guard let m = bindings.message else { return false }
                let who = [m.senderAddress, m.sender].compactMap { $0?.lowercased() }
                return d.inReplyTo == m.id && d.recipients.contains { r in who.contains { r.lowercased().contains($0) || $0.contains(r.lowercased()) } }
            }
            if let recipient, !recipient.isEmpty {
                return d.recipients.contains { $0.lowercased().contains(recipient.lowercased()) }
            }
            return true
        case (.draftShown, .reviewShown(let d)):
            if let ch = step.channel, d.channel != ch { return false }
            return bindings.draft.map { $0.id == d.id } ?? true
        case (.sent, .sent(let draftID, _)), (.sent, .sendRehearsed(let draftID)):
            return bindings.approval?.draftID == draftID
        default:
            return false
        }
    }

    static let queryStopwords: Set<String> = [
        "the", "a", "an", "my", "email", "emails", "message", "messages", "mail", "from", "about", "latest", "last", "newest",
        "recent", "new", "unread", "s", "to", "of", "on", "in",
    ]

    /// At least one meaningful spoken word appears in the sender or subject.
    static func matches(query: String, _ m: MessageRef) -> Bool {
        let words = tokens(query).filter { !queryStopwords.contains($0) }
        guard !words.isEmpty else { return true }
        let hay = Set(tokens(m.sender + " " + (m.senderAddress ?? "") + " " + m.subject))
        return words.contains { hay.contains($0) }
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "'s", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// "the first one", "2", "number two", "Sarah Chen", "the one about lunch".
    static func choose(_ utterance: String, from candidates: [MessageRef]) -> MessageRef? {
        let words = tokens(utterance)
        let ordinals: [String: Int] = [
            "first": 0, "one": 0, "1": 0, "second": 1, "two": 1, "2": 1, "third": 2, "three": 2, "3": 2,
            "fourth": 3, "four": 3, "4": 3, "fifth": 4, "five": 4, "5": 4, "last": candidates.count - 1,
        ]
        for w in words { if let i = ordinals[w], candidates.indices.contains(i) { return candidates[i] } }
        let meaningful = Set(words).subtracting(queryStopwords).subtracting(["one", "that", "this", "it", "please"])
        guard !meaningful.isEmpty else { return nil }
        let scored = candidates.map { c in
            (c, meaningful.intersection(tokens(c.sender + " " + c.subject + " " + (c.date ?? ""))).count)
        }
        let best = scored.map(\.1).max() ?? 0
        let top = scored.filter { $0.1 == best && best > 0 }
        return top.count == 1 ? top[0].0 : nil  // a tie is not an answer
    }

    /// Candidates tied for the best word match when that tie is a strict subset (≥2) of the
    /// list, i.e. the answer narrowed the choice without deciding it.
    static func narrow(_ utterance: String, from candidates: [MessageRef]) -> [MessageRef]? {
        let meaningful = Set(tokens(utterance)).subtracting(queryStopwords)
            .subtracting(["one", "that", "this", "it", "please", "i", "meant", "mean", "yeah", "yes", "no", "the"])
        guard !meaningful.isEmpty else { return nil }
        let scored = candidates.map { c in (c, meaningful.intersection(tokens(c.sender + " " + c.subject + " " + (c.date ?? ""))).count) }
        let best = scored.map(\.1).max() ?? 0
        let top = scored.filter { $0.1 == best && best > 0 }.map(\.0)
        return top.count >= 2 && top.count < candidates.count ? top : nil
    }

}
