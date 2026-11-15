import FlowCore
import FlowLLM
import Foundation

/// A model classifier that reports its per-attempt evidence. `BonsaiIntentClassifier` conforms.
public protocol TracedIntentClassifying: Sendable {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace
}

extension BonsaiIntentClassifier: TracedIntentClassifying {}

/// One routing decision with the evidence of how it was made.
public struct RoutingDecision: Sendable {
    public let outcome: Result<Intent, ClassificationError>
    public let stage: RouteStage
    /// Present when the model was consulted.
    public let trace: ClassificationTrace?
    /// Set when the decision is a question whose answer should complete an action.
    public let pending: PendingQuestion?
}

/// Stateless routing pipeline (spec 02 §2 `IntentRouter`):
///
/// 1. control phrases (stop/cancel), never the model;
/// 2. answer to a pending clarification (takes precedence over a bare number);
/// 2b. numbered-overlay phrases (show/hide numbers, choose N), never the model;
/// 3. decline actions that do not exist (close/delete);
/// 4. references ("it", "that window", "her") resolved against context, or a question;
/// 5. deterministic fast path for explicit simple commands (verbatim slots);
/// 6. Bonsai, then grounding/consistency guards; missing slots become questions.
public struct IntentRouterCore: Sendable {
    public let model: any TracedIntentClassifying

    public init(model: any TracedIntentClassifying) {
        self.model = model
    }

    public func route(_ utterance: String, context: ConversationContext) async -> RoutingDecision {
        let raw = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return decision(.failure(.emptyInput), .clarify) }
        guard raw.count <= BonsaiIntentClassifier.maxInputLength else {
            return decision(.failure(.inputTooLong(limit: BonsaiIntentClassifier.maxInputLength)), .clarify)
        }

        if let control = DeterministicRouter.route(raw) { return decision(.success(control), .control) }

        let s = Cleaner.clean(raw)
        guard !s.isEmpty else { return decision(.failure(.emptyInput), .clarify) }

        if let pending = context.pending, let answer = Rules.answer(s, to: pending) {
            return decision(.success(answer), .followUp)
        }
        if let hit = Rules.overlay(s) ?? Rules.draftDiscard(s, context) ?? Rules.draftReview(s, context)
            ?? Rules.draftEdit(raw: raw, cleaned: s, context) ?? Rules.windowControl(s, context) ?? Rules.unsupported(s)
            ?? Rules.references(s, context)
            ?? Rules.fastPath(s) {
            let intent = Self.restoreTerminalMark(hit.intent, Cleaner.terminalMark(raw))
            if let confirm = Guard.confirmTime(intent) {
                return RoutingDecision(outcome: .success(confirm.intent), stage: .clarify, trace: nil, pending: confirm.pending)
            }
            return RoutingDecision(outcome: .success(intent), stage: hit.stage, trace: nil, pending: hit.pending)
        }

        let trace = await model.classifyTraced(s)
        switch trace.outcome {
        case .success(let intent):
            // The model asked its own question about something calendar-shaped ("Which day are
            // you asking about?"): ask Flow's question instead, so the answer is understood.
            if intent.kind == .clarification, intent.action == nil, Guard.soundsLikeCalendar(s) {
                return RoutingDecision(outcome: .success(Make.ask("Which day or time should I check?")), stage: .guarded, trace: trace,
                                       pending: .calendarTime)
            }
            if let hit = Guard.check(intent, utterance: s, context: context) {
                return RoutingDecision(outcome: .success(hit.intent), stage: hit.stage, trace: trace, pending: hit.pending)
            }
            if let confirm = Guard.confirmTime(intent) {
                return RoutingDecision(outcome: .success(confirm.intent), stage: .guarded, trace: trace, pending: confirm.pending)
            }
            return RoutingDecision(outcome: .success(intent), stage: .model, trace: trace, pending: nil)
        case .failure(let error):
            if let hit = Guard.question(for: error, rawContent: trace.attempts.last?.rawContent) {
                return RoutingDecision(outcome: .success(hit.intent), stage: hit.stage, trace: trace, pending: hit.pending)
            }
            return RoutingDecision(outcome: .failure(error), stage: .model, trace: trace, pending: nil)
        }
    }

    /// Dictated content ends where the utterance ends, so a spoken "?"/"!" belongs to it.
    static func restoreTerminalMark(_ intent: Intent, _ mark: String) -> Intent {
        guard !mark.isEmpty, let action = intent.action else { return intent }
        let updated: FlowAction
        switch action {
        case .createDraft(let r, let c) where !c.isEmpty: updated = .createDraft(recipient: r, content: c + mark)
        case .insertText(let t): updated = .insertText(t + mark)
        default: return intent
        }
        return Intent(id: intent.id, kind: intent.kind, action: updated, summary: intent.summary, source: intent.source)
    }

    private func decision(_ outcome: Result<Intent, ClassificationError>, _ stage: RouteStage) -> RoutingDecision {
        RoutingDecision(outcome: outcome, stage: stage, trace: nil, pending: nil)
    }
}

/// Stateful router: keeps a `ConversationContext` across utterances.
///
/// Context is updated from the intents this router *proposes*. Track A can replace it
/// with executor-verified state through `updateContext(_:)`. Context older than
/// `contextTTL` is ignored, so stale references are never resolved silently.
public actor IntentRouter: IntentClassifying {
    public nonisolated let core: IntentRouterCore
    public nonisolated let contextTTL: TimeInterval
    public private(set) var context: ConversationContext
    private let now: @Sendable () -> Date

    public init(
        model: any TracedIntentClassifying, context: ConversationContext = .empty, contextTTL: TimeInterval = 600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.core = IntentRouterCore(model: model)
        self.context = context
        self.contextTTL = contextTTL
        self.now = now
    }

    public func classify(_ utterance: String) async throws(ClassificationError) -> Intent {
        try await route(utterance).outcome.get()
    }

    public func route(_ utterance: String) async -> RoutingDecision {
        let at = now()
        let current = context.fresh(now: at, ttl: contextTTL)
        let decision = await core.route(utterance, context: current)
        context = Self.apply(decision, to: current, now: at)
        return decision
    }

    /// Replace the context, e.g. with state verified by the executor.
    public func updateContext(_ new: ConversationContext) { context = new }

    public func resetContext() { context = .empty }

    /// Abandon an open clarification question (stop/cancel handled outside the router).
    public func cancelPendingQuestion() { context.pending = nil }

    static func apply(_ decision: RoutingDecision, to old: ConversationContext, now: Date) -> ConversationContext {
        var ctx = old
        guard case .success(let intent) = decision.outcome else { return ctx }
        if intent.kind == .control {
            ctx.pending = nil  // stop/cancel also abandons an open question
            return ctx
        }
        ctx.pending = decision.pending
        if let action = intent.action { ctx.record(action, now: now) } else { ctx.updatedAt = now }
        return ctx
    }
}
