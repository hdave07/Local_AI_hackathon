import FlowCore
import FlowLLM
@testable import FlowPlanner
import FlowRouting
import Foundation

/// The planner must work without any model output; this stand-in answers nothing.
struct NoModel: TracedIntentClassifying {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        ClassificationTrace(outcome: .failure(.serverUnavailable("no model in tests")), attempts: [])
    }
}

enum Fixture {
    static let sarahChen = MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", senderAddress: "sarah.chen@example.com",
                                      subject: "Meeting tomorrow", date: "today 9:14", epoch: 1)
    static let sarahPatel = MessageRef(channel: .mail, id: "m2", sender: "Sarah Patel", senderAddress: "sarah.p@example.com",
                                       subject: "Tomorrow's lunch", date: "yesterday", epoch: 1)
    static let priya = MessageRef(channel: .mail, id: "m3", sender: "Priya Rao", senderAddress: "priya@example.com",
                                  subject: "Invoice 42", epoch: 1)
    static let leeWhatsApp = MessageRef(channel: .whatsapp, id: "w1", sender: "Lee", senderAddress: "+1 555 0100",
                                        subject: "Running late", epoch: 1)
    static let danaText = MessageRef(channel: .messages, id: "t1", sender: "Dana", senderAddress: "+1 555 0199",
                                     subject: "Friday?", epoch: 1)

    static func world() -> MockExecutor.World {
        MockExecutor.World(activeApp: .notes, messages: [sarahChen, sarahPatel, priya, leeWhatsApp, danaText])
    }

    static let acceptance = "Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me."
}

/// A session wired to a mock executor and a controllable clock.
struct Harness {
    let session: TaskSession
    let mock: MockExecutor
    let store: IntentRouter
    let clock: TestClock

    init(world: MockExecutor.World = Fixture.world()) {
        let clock = TestClock()
        self.clock = clock
        mock = MockExecutor(world: world)
        store = IntentRouter(model: NoModel(), now: { clock.now })
        session = TaskSession(store: store, executor: mock, now: { clock.now })
    }

    func say(_ s: String) async -> SessionReply { await session.handle(s) }
    var state: RunState { get async { await session.runner.state } }
    var context: ConversationContext { get async { await store.context } }
    var requests: [ExecutionRequest] { get async { await mock.requests } }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { t } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t = t.addingTimeInterval(seconds) } }
}

extension RunState {
    var isCompleted: Bool { if case .completed = self { true } else { false } }
    var isCancelled: Bool { if case .cancelled = self { true } else { false } }
    var stopReason: String? { if case .stopped(_, let r) = self { r } else { nil } }
    var question: PlanQuestion? { if case .awaitingChoice(let q) = self { q } else { nil } }
    var approvalRequest: ApprovalRequest? { if case .awaitingConfirmation(let r) = self { r } else { nil } }
}
