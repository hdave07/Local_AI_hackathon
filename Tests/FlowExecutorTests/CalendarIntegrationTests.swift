import FlowCalendar
import FlowCore
@testable import FlowExecutor
import FlowLLM
import FlowPlanner
import FlowRouting
import Foundation
import Testing

/// Calendar questions through the real TaskSession (router + planner) and real executor,
/// over a simulated EventKit store, at a fixed "now" (Sat 14 Nov 2026, noon New York).
@MainActor
@Suite("Calendar: TaskSession + MacPlanExecutor")
struct CalendarIntegrationTests {
    struct NoModel: TracedIntentClassifying {
        func classifyTraced(_ utterance: String) async -> ClassificationTrace {
            ClassificationTrace(outcome: .success(Intent(kind: .unsupported, summary: "I didn't understand that.", source: .model(id: "none"))),
                                attempts: [])
        }
    }

    @MainActor
    struct Flow {
        let store: FakeCalendarStore
        let viewer: FakeViewer
        let executor: MacPlanExecutor
        let session: TaskSession

        init() {
            store = FakeCalendarStore()
            viewer = FakeViewer()
            store.eventsByCalendar["c-test"] = [
                CalendarEventInfo(id: "coffee", title: "[FlowTest] Coffee with Sarah", start: ny(11, 15, 16), end: ny(11, 15, 17)),
                CalendarEventInfo(id: "cancel", title: "[FlowTest] Cancelled standup", start: ny(11, 18, 10), end: ny(11, 18, 11), status: .canceled),
            ]
            store.eventsByCalendar["c-home"] = [CalendarEventInfo(id: "home", title: "Private", start: ny(11, 18, 10), end: ny(11, 18, 11), calendarTitle: "Home")]
            let rig = Rig()
            let now = saturdayNoon
            let calendar = CalendarController(store: store, scope: .named(["FlowTest"]), viewer: viewer, calendar: newYork, now: { now })
            executor = MacPlanExecutor(window: rig.executor.engineWindow, navigator: rig.executor.engineNavigator,
                                       mail: rig.executor.engineMail, calendar: calendar)
            session = TaskSession(store: IntentRouter(model: NoModel()), executor: executor)
        }
    }

    @Test func busyAtFourTomorrowWithStructuredEvidence() async throws {
        let f = Flow()
        let r = await f.session.handle("Do I have anything at 4 tomorrow?")
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        #expect(r.say == ["In your FlowTest calendar, you're busy tomorrow (Sun 15 Nov) at 4:00 PM: [FlowTest] Coffee with Sarah (4:00 PM–5:00 PM). (I took that as 4:00 PM.)"])
        let entry = try #require(f.executor.log.last)
        #expect(entry.action == "query_calendar")
        #expect(entry.observation == "availability: busy, 1 event(s), calendars 1")
        #expect(!entry.userMessage.contains("Coffee"), "event titles stay out of the log")
        #expect(f.viewer.shown.isEmpty, "answering never opens Calendar")
    }

    /// Voice session 2026-11-15: spoken lead-ins, a missing time answered with "today", and
    /// "what about …" follow-ups must all reach the calendar.
    @Test func spokenFollowUpsReachTheCalendar() async {
        let f = Flow()
        var r = await f.session.handle("No, I mean like do I have anything at four tomorrow?")
        #expect(r.say.first?.contains("Coffee with Sarah") == true, "\(r.say)")
        r = await f.session.handle("What about Wednesday at 10?")
        #expect(r.say.first?.hasPrefix("Nothing is scheduled Wed 18 Nov at 10:00 AM in your FlowTest calendar") == true, "\(r.say)")
        r = await f.session.handle("Do I have anything")
        #expect(r.say == ["Which day or time should I check?"])
        r = await f.session.handle("Uh, tomorrow.")
        #expect(r.say.first?.contains("Coffee with Sarah") == true, "\(r.say)")
        _ = await f.session.handle("open notes")
        r = await f.session.handle("tomorrow")
        #expect(r.say.first?.contains("Coffee") != true, "a bare day without calendar context isn't a calendar question")
    }

    @Test(arguments: ["Am I free tomorrow at 4?", "Check whether I have anything at four tomorrow"])
    func flagshipPhrasings(utterance: String) async {
        let r = await Flow().session.handle(utterance)
        #expect(r.say.first?.contains("you're busy tomorrow (Sun 15 Nov) at 4:00 PM") == true, "\(r.say)")
    }

    @Test func cancelledEventsDoNotBlockAndOnlyFlowTestIsRead() async {
        let f = Flow()
        let r = await f.session.handle("Am I busy at 10 am on Wednesday?")
        #expect(r.say.first?.hasPrefix("Nothing is scheduled Wed 18 Nov at 10:00 AM in your FlowTest calendar, so you look free.") == true, "\(r.say)")
        #expect(r.say.first?.contains("Cancelled standup (cancelled)") == true)
        #expect(f.store.queriedIDs.allSatisfy { $0 == ["c-test"] }, "the Home calendar is never read")
    }

    @Test func deniedAccessIsAClearUnknownNeverFree() async {
        let f = Flow()
        f.store.accessValue = .denied
        let r = await f.session.handle("Do I have anything at 4 tomorrow?")
        guard case .stopped(_, let reason) = r.state else { Issue.record("state \(r.state)"); return }
        #expect(reason.hasPrefix("I can't tell"))
        #expect(!reason.contains("free."))
    }

    @Test func showTheDayOnlyWhenAsked() async {
        let f = Flow()
        let r = await f.session.handle("Show me tomorrow on my calendar")
        guard case .completed = r.state else { Issue.record("state \(r.state) say \(r.say)"); return }
        #expect(f.viewer.shown == [ny(11, 15, 0)])
        #expect(f.store.queriedIDs.isEmpty, "showing a day reads no events")
    }

    @Test func unknownTimeAsks() async {
        let r = await Flow().session.handle("What's on my calendar")
        #expect(r.say.first == "Which day or time should I check?")
    }
}
