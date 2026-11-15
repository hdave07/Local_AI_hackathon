import FlowCore
import FlowRouting
import Foundation

/// What Flow says and where the task stands after one utterance.
public struct SessionReply: Sendable, Equatable {
    public let say: [String]
    public let state: RunState
    public let plan: Plan?
}

/// One utterance in → cancel, answer a paused plan, or plan and run new work.
///
/// Holds no state of its own: task state lives in the router's `ConversationContext`
/// (single store) and run state in `PlanRunner`.
public actor TaskSession {
    public let store: IntentRouter
    public let planner: TaskPlanner
    public let runner: PlanRunner
    private let executor: any PlanExecuting
    private let now: @Sendable () -> Date

    public init(store: IntentRouter, executor: any PlanExecuting, catalog: ChannelCatalog = .standard,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.planner = TaskPlanner(router: store.core, catalog: catalog)
        self.runner = PlanRunner(executor: executor, store: store, now: now)
        self.executor = executor
        self.now = now
    }

    public func handle(_ utterance: String) async -> SessionReply {
        // 1. stop / cancel always win, without any model call (spec 02 §3).
        if let control = DeterministicRouter.route(utterance), control.control == .stop || control.control == .cancel {
            let hadQuestion = await store.context.pending != nil
            var say = await runner.cancel()
            // Also drop an open router question ("What should the reply say?"), so the next
            // utterance is a new command, not an answer.
            await store.cancelPendingQuestion()
            if say.isEmpty { say = [hadQuestion ? "Okay, never mind." : "Nothing to stop."] }
            return await reply(say, plan: nil)
        }

        // 2. A paused plan gets first look at the utterance.
        var say: [String] = []
        if await runner.state.isPaused {
            switch await runner.answer(utterance) {
            case .handled(let messages):
                return await reply(messages, plan: await runner.plan)
            case .notAnAnswer:
                if case .awaitingConfirmation = await runner.state {
                    // Anything but yes/no cancels the pending send; an edit must be reviewed again.
                    await runner.abandon("Okay, I won't send it yet.")
                    say.append("Okay, I won't send it yet.")
                }
            }
        }

        // 3. Plan new work against fresh task context.
        let ctx = await store.context.fresh(now: now(), ttl: store.contextTTL)
        let outcome = await planner.plan(utterance, context: ctx)
        if case .plan(let plan) = outcome, Self.isSideStep(plan) {
            // "Switch to Calendar" while Flow waits for an answer: run it and keep the question
            // (ADR 0011). A send confirmation was already abandoned above; nothing is ever approved here.
            if case .awaitingChoice(let q) = await runner.state {
                let side = PlanRunner(executor: executor, store: store, now: now)
                say += await side.start(plan)
                return await reply(say + ["Still waiting. " + q.prompt], plan: await runner.plan)
            }
            let open = await store.context
            if let pending = open.pending, Self.survivesSideStep(pending) {
                say += await runner.start(plan)
                var c = await store.context
                c.pending = pending  // keep the router question open
                c.pendingPrompt = open.pendingPrompt
                await store.updateContext(c)
                return await reply(say + (open.pendingPrompt.map { ["Still waiting. " + $0] } ?? []), plan: plan)
            }
        }
        if case .awaitingChoice(let q) = await runner.state {
            if case .plan = outcome {} else {
                // Neither an answer nor a new task: repeat the open question.
                return await reply(say + ["Sorry, which one? " + q.options.joined(separator: "; ")], plan: await runner.plan)
            }
        }
        switch outcome {
        case .plan(let plan):
            await clearRouterQuestion()
            say += await runner.start(plan)
            return await reply(say, plan: plan)
        case .clarification(let intent, let pending):
            var c = await store.context
            c.pending = pending
            c.pendingPrompt = pending == nil ? nil : intent.summary
            await store.updateContext(c)
            return await reply(say + [intent.summary], plan: nil)
        case .declined(let intent):
            await clearRouterQuestion()
            return await reply(say + [intent.summary], plan: nil)
        case .control(let intent):
            return await reply(say + [intent.summary], plan: nil)
        case .failure(let error):
            return await reply(say + [error.userMessage], plan: nil)
        }
    }

    /// Router questions that a quick app command does not answer ("Which app?" it does answer).
    static func survivesSideStep(_ pending: PendingQuestion) -> Bool {
        switch pending {
        case .plan, .app: false
        case .person, .position, .textToReplace, .confirm, .draftContent, .calendarTime, .textEdit: true
        }
    }

    /// A one-step app or window command that does not change the task being answered.
    static func isSideStep(_ plan: Plan) -> Bool {
        guard plan.steps.count == 1, let action = plan.steps.first?.action else { return false }
        switch action {
        case .activateApp, .minimizeWindow, .restoreWindow, .listWindows, .moveWindow, .resizeWindow, .tileWindows: return true
        default: return false
        }
    }

    private func clearRouterQuestion() async {
        var c = await store.context
        if c.pending != nil, !({ if case .plan = c.pending { true } else { false } }()) {
            c.pending = nil
            await store.updateContext(c)
        }
    }

    private func reply(_ say: [String], plan: Plan?) async -> SessionReply {
        SessionReply(say: say, state: await runner.state, plan: plan)
    }
}
