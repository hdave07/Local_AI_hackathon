// flow-plan-demo — Track B planner walkthrough against the MOCK executor.
//
//   swift run flow-plan-demo            # scripted scenarios, deterministic (no model, no macOS)
//   swift run flow-plan-demo --bonsai   # same, with Bonsai via LM Studio as the router fallback
//
// Prints each plan, Flow's replies, and every request the executor received. Nothing is
// executed on macOS: the executor is `MockExecutor`.

import FlowCore
import FlowLLM
import FlowPlanner
import FlowRouting
import Foundation

/// Model disabled: anything the deterministic router does not handle is declined.
struct Silent: TracedIntentClassifying {
    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        let intent = Intent(kind: .unsupported, summary: "I didn't understand that (model disabled in this demo).",
                            source: .model(id: "none"))
        return ClassificationTrace(outcome: .success(intent), attempts: [])
    }
}

func short(_ state: RunState) -> String {
    switch state {
    case .idle: "idle"
    case .running(_, let step): "running step \(step)"
    case .awaitingChoice: "paused: waiting for a choice"
    case .awaitingConfirmation: "paused: waiting for confirmation"
    case .completed: "completed"
    case .stopped(_, let reason): "stopped (\(reason))"
    case .cancelled: "cancelled"
    }
}

let useBonsai = CommandLine.arguments.contains("--bonsai")
func model() -> any TracedIntentClassifying {
    guard useBonsai, let config = try? LMStudioConfiguration() else { return Silent() }
    return BonsaiIntentClassifier(client: LMStudioClient(configuration: config))
}

let world = MockExecutor.World(activeApp: .notes, messages: [
    MessageRef(channel: .mail, id: "m1", sender: "Sarah Chen", senderAddress: "sarah.chen@example.com", subject: "Meeting tomorrow",
               date: "today 9:14", epoch: 1),
    MessageRef(channel: .mail, id: "m2", sender: "Sarah Patel", senderAddress: "sarah.p@example.com", subject: "Tomorrow's lunch",
               date: "yesterday", epoch: 1),
    MessageRef(channel: .whatsapp, id: "w1", sender: "Lee", senderAddress: "+1 555 0100", subject: "Running late", epoch: 1),
])

func describe(_ r: ExecutionRequest) -> String {
    var s = "    → executor: \(r.action.type.rawValue)"
    if let ch = r.channel { s += " [\(ch)]" }
    if let m = r.bindings.message { s += " message=\(m.id)" }
    if let d = r.bindings.draft { s += " draft=\(d.id)v\(d.version)" }
    if let a = r.bindings.approval { s += " approval(draft \(a.draftID) v\(a.draftVersion) hash \(a.contentHash.prefix(8))…)" }
    return s
}

func run(_ title: String, _ script: [String]) async {
    print("\n══ \(title)")
    let mock = MockExecutor(world: world)
    let store = IntentRouter(model: model())
    let session = TaskSession(store: store, executor: mock)
    var seen = 0
    var lastPlan: UUID?
    for line in script {
        print("\nUSER: \(line)")
        let reply = await session.handle(line)
        if let plan = reply.plan, plan.id != lastPlan {
            lastPlan = plan.id
            for s in plan.steps {
                let deps = s.dependsOn.isEmpty ? "" : " after \(s.dependsOn.map(String.init).joined(separator: ","))"
                let flags = [s.origin == .implied ? "implied" : nil, s.requiresConfirmation ? "needs confirmation" : nil,
                             "risk \(s.risk.rawValue)"].compactMap { $0 }.joined(separator: ", ")
                print("  plan[\(s.id)] \(s.summary)\(s.channel.map { " [\($0)]" } ?? "")\(deps) (\(flags))")
            }
        }
        let requests = await mock.requests
        for r in requests.dropFirst(seen) { print(describe(r)) }
        seen = requests.count
        for say in reply.say { print("FLOW: \(say)") }
        print("  state: \(short(reply.state))")
    }
    let sent = await mock.world.sent
    print("  sent: \(sent.count) message(s)" + (sent.isEmpty ? "" : " — " + sent.map { "\($0.channel) \($0.draftID)" }.joined(separator: ", ")))
}

await run("Acceptance: find, choose, reply, review — then confirm send", [
    "Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.",
    "the first one",
    "send it",
    "yes",
    "send it",
])
await run("Edit while confirming invalidates the approval", [
    "Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.",
    "Sarah Chen",
    "send it",
    "change 3 to 3:30",
    "send it",
    "yes",
])
await run("Same planner, WhatsApp channel", [
    "find Lee's whatsapp message, reply saying see you soon, and show it to me",
    "send it",
    "no",
])
await run("Stop while choosing", [
    "Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.",
    "stop",
    "the first one",
])
