import FlowCore
import FlowPlanner
import FlowRouting
import Testing

/// The milestone phrases (including recognizer output with fillers) plan deterministically,
/// with the model disabled.
@Suite("Milestone phrase plans")
struct PlanProbeTests {
    @Test(arguments: ["Open Notes", "open notes.", "Um, open notes", "um open notes"])
    func openNotes(utterance: String) async {
        let planner = TaskPlanner(router: IntentRouter(model: SilentModel()).core)
        guard case .plan(let p) = await planner.plan(utterance, context: .empty) else { Issue.record("no plan"); return }
        #expect(p.steps.map(\.action) == [.activateApp(.notes)])
        #expect(p.steps.first?.expectation == .appFrontmost(.notes))
    }

    @Test(arguments: [
        ("Find Sarah's email", "Sarah's email"),
        ("Can you find Sarah's email?", "Sarah's email"),
        ("Uh, find Sarah's email", "Sarah's email"),
        ("find sarah's email in the flowtest mailbox", "sarah's email in the flowtest mailbox"),
        ("Find the email from Priya", "email from Priya"),
    ])
    func findMail(utterance: String, query: String) async {
        let planner = TaskPlanner(router: IntentRouter(model: SilentModel()).core)
        guard case .plan(let p) = await planner.plan(utterance, context: .empty) else { Issue.record("no plan"); return }
        #expect(p.steps.map(\.action) == [.activateApp(.mail), .readMessage(query: query)])
        #expect(p.steps.last?.channel == .mail)
    }
}
