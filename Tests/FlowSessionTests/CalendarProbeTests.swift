import FlowCore
import FlowPlanner
import FlowRouting
import Testing

/// Calendar phrasings plan deterministically (model disabled): questions answer, "show" navigates.
@Suite("Calendar phrase plans")
struct CalendarPhrasePlanTests {
    @Test(arguments: [
        ("What's on my calendar tomorrow?", "tomorrow"),
        ("Do I have anything at four?", "at four"),
        ("Am I free Friday afternoon?", "Friday afternoon"),
        ("Do I have anything at 4 tomorrow?", "at 4 tomorrow"),
        ("Check whether I have anything at four tomorrow", "at four tomorrow"),
        ("Is anything scheduled at 10 am on Tuesday?", "at 10 am on Tuesday"),
        ("Am I free tomorrow at 4?", "tomorrow at 4"),
    ])
    func questionsOnlyQuery(utterance: String, time: String) async {
        let planner = TaskPlanner(router: IntentRouter(model: SilentModel()).core)
        guard case .plan(let p) = await planner.plan(utterance, context: .empty) else { Issue.record("no plan"); return }
        #expect(p.steps.map(\.action) == [.queryCalendar(timeExpression: time)])
    }

    @Test(arguments: [("Show me tomorrow on my calendar", "tomorrow"), ("open my calendar to Friday", "Friday"),
                      ("show my calendar for Monday", "Monday")])
    func showRequestsNavigate(utterance: String, day: String) async {
        let planner = TaskPlanner(router: IntentRouter(model: SilentModel()).core)
        guard case .plan(let p) = await planner.plan(utterance, context: .empty) else { Issue.record("no plan"); return }
        #expect(p.steps.map(\.action) == [.showCalendar(dateExpression: day)])
    }
}
