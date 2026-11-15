import FlowCore
import FlowLLM
@testable import FlowRouting
import Foundation
import Synchronization
import Testing

/// Model double: canned answers per (cleaned) utterance; records every call.
final class FakeModel: TracedIntentClassifying {
    private let answers: [String: Result<Intent, ClassificationError>]
    private let raw: [String: String]
    private let log = Mutex<[String]>([])

    init(_ answers: [String: Result<Intent, ClassificationError>] = [:], raw: [String: String] = [:]) {
        self.answers = answers
        self.raw = raw
    }

    var calls: [String] { log.withLock { $0 } }

    func classifyTraced(_ utterance: String) async -> ClassificationTrace {
        log.withLock { $0.append(utterance) }
        let outcome = answers[utterance.lowercased()] ?? .failure(.unsupportedAction("unscripted"))
        let error: ClassificationError? = if case .failure(let e) = outcome { e } else { nil }
        return ClassificationTrace(
            outcome: outcome,
            attempts: [.init(rawContent: raw[utterance.lowercased()], error: error, latency: .milliseconds(450))])
    }
}

func modelIntent(_ action: FlowAction?, kind: IntentKind = .direct) -> Intent {
    Intent(kind: kind, action: action, summary: "m", source: .model(id: "bonsai"))
}

func route(_ s: String, _ ctx: ConversationContext = .empty, model: FakeModel = FakeModel()) async -> RoutingDecision {
    await IntentRouterCore(model: model).route(s, context: ctx)
}

@Suite("Fast path: explicit simple commands never call the model")
struct FastPathTests {
    @Test(arguments: [
        ("Open Notes.", FlowAction.activateApp(.notes)),
        ("open mail", .activateApp(.mail)),
        ("Flow, launch calendar", .activateApp(.calendar)),
        ("can you switch to safari please", .activateApp(.safari)),
        ("show me the finder app", .activateApp(.finder)),
        ("put mail and calendar side by side", .tileWindows(left: .mail, right: .calendar)),
        ("put notes on the left and safari on the right", .tileWindows(left: .notes, right: .safari)),
        ("put safari on the right and notes on the left", .tileWindows(left: .notes, right: .safari)),
        ("tile calendar and mail", .tileWindows(left: .calendar, right: .mail)),
        ("move this window to the left half", .moveWindow(.active, .leftHalf)),
        ("snap the mail window to the right", .moveWindow(.app(.mail), .rightHalf)),
        ("maximize the mail window", .moveWindow(.app(.mail), .maximize)),
        ("make the notes window full screen", .moveWindow(.app(.notes), .maximize)),
        ("center this window", .moveWindow(.active, .center)),
        ("make this window a little wider", .resizeWindow(.active, .wider)),
        ("make the calendar window smaller", .resizeWindow(.app(.calendar), .smaller)),
        ("scroll down", .scroll(.down)),
        ("scroll up a bit", .scroll(.up)),
        ("scroll to the top", .scroll(.top)),
        ("go to the bottom of the page", .scroll(.bottom)),
        ("send it", .requestSend),
        ("let me review the draft", .requestReview),
        ("click send", .requestSend),
    ])
    func routesDeterministically(utterance: String, expected: FlowAction) async throws {
        let model = FakeModel()
        let d = await route(utterance, model: model)
        #expect(try d.outcome.get().action == expected)
        #expect(try d.outcome.get().source == .deterministic)
        #expect(d.stage == .fastPath)
        #expect(model.calls.isEmpty)
    }

    @Test(arguments: [
        ("find sarah's email about tomorrow", "sarah's email about tomorrow"),
        ("open the latest email from john", "latest email from john"),
        ("search my mail for the budget report", "the budget report"),
        ("show me the email from alex about the offsite", "email from alex about the offsite"),
    ])
    func emailSearchIsNeverCalendar(utterance: String, query: String) async throws {
        let d = await route(utterance)
        #expect(try d.outcome.get().action == .readMessage(query: query))
    }

    @Test(arguments: [
        ("do I have anything at four tomorrow", "at four tomorrow"),
        ("am I free on Friday afternoon", "on Friday afternoon"),
        ("what's on my calendar on thursday", "on thursday"),
    ])
    func calendarTimeIsCopiedVerbatim(utterance: String, time: String) async throws {
        #expect(try await route(utterance).outcome.get().action == .queryCalendar(timeExpression: time))
    }

    @Test func calendarWithoutTimeAsks() async throws {
        let d = await route("check my schedule")
        #expect(try d.outcome.get().kind == .clarification)
    }

    @Test func embeddedCommandsFallThroughToTheModel() async {
        let model = FakeModel()
        _ = await route("open notes and then put mail on the left", model: model)
        #expect(model.calls == ["open notes and then put mail on the left"])
    }
}

@Suite("Slots are preserved exactly")
struct SlotPreservationTests {
    @Test(arguments: [
        ("Reply to Sarah: Thanks, see you at 4:30 on the 12th.", "Sarah", "Thanks, see you at 4:30 on the 12th"),
        ("reply to sarah that I can meet tomorrow", "sarah", "I can meet tomorrow"),
        ("Email Dana: are you free on the 12th?", "Dana", "are you free on the 12th?"),
        ("email John saying the Q3 report is ready", "John", "the Q3 report is ready"),
        ("send an email to Marco that the meeting moved to 3:45", "Marco", "the meeting moved to 3:45"),
        ("write to alex and ask if friday works", "alex", "ask if friday works"),
        ("write an email to Dana asking whether the 12th still works", "Dana", "asking whether the 12th still works"),
        ("tell Lee I'll be ten minutes late", "Lee", "I'll be ten minutes late"),
        ("email sarah", "sarah", ""),
    ])
    func draftRecipientAndContentAreVerbatim(utterance: String, recipient: String, content: String) async throws {
        let d = await route(utterance)
        #expect(try d.outcome.get().action == .createDraft(recipient: recipient, content: content))
    }

    @Test func editsKeepTimesExactly() async throws {
        #expect(try await route("change 3 to 3:30").outcome.get().action == .replaceText(old: "3", new: "3:30"))
        #expect(try await route("replace 2 pm with 2:30 pm").outcome.get().action == .replaceText(old: "2 pm", new: "2:30 pm"))
        #expect(try await route("type Hello, Everyone!").outcome.get().action == .insertText("Hello, Everyone!"))
    }

    @Test func replyAllIsNeverSilent() async throws {
        #expect(try await route("reply to all saying thanks").outcome.get().kind == .clarification)
    }
}

@Suite("Control phrases stay deterministic")
struct ControlTests {
    @Test(arguments: ["stop", "Cancel.", "Flow, stop.", "flow stop dictation"])
    func controlNeverCallsTheModel(phrase: String) async throws {
        let model = FakeModel()
        let d = await route(phrase, model: model)
        #expect(try d.outcome.get().kind == .control)
        #expect(d.stage == .control)
        #expect(model.calls.isEmpty)
    }

    @Test func stopAbandonsAPendingQuestion() async throws {
        let router = IntentRouter(model: FakeModel())
        _ = await router.route("open it")
        #expect(await router.context.pending != nil)
        _ = await router.route("stop")
        #expect(await router.context.pending == nil)
        // The next word is not taken as an answer.
        let d = await router.route("notes")
        #expect(d.stage != .followUp)
    }
}

@Suite("References and clarification")
struct ReferenceTests {
    @Test func openItUsesTheActiveApp() async throws {
        let d = await route("open it", ConversationContext(activeApp: .notes))
        #expect(try d.outcome.get().action == .activateApp(.notes))
        #expect(d.stage == .context)
    }

    @Test func openItWithoutContextAsksAndRemembersTheQuestion() async throws {
        let model = FakeModel()
        let d = await route("open it", model: model)
        #expect(try d.outcome.get().kind == .clarification)
        #expect(d.pending == .app(then: .activate))
        #expect(model.calls.isEmpty)
    }

    @Test func pronounRecipientNeedsExactlyOnePerson() async throws {
        let one = await route("reply to her saying sounds good", ConversationContext(recentPeople: ["Marco"]))
        #expect(try one.outcome.get().action == .createDraft(recipient: "Marco", content: "sounds good"))

        let none = await route("reply to her")
        #expect(try none.outcome.get().kind == .clarification)

        let two = await route("reply to her", ConversationContext(recentPeople: ["Sarah", "Sam"]))
        let question = try two.outcome.get()
        #expect(question.kind == .clarification)
        #expect(question.summary.contains("Sarah") && question.summary.contains("Sam"))
        #expect(two.pending == .person(candidates: ["Sarah", "Sam"], then: .draft(content: "")))
    }

    @Test func explicitNamesOverrideContext() async throws {
        let d = await route("reply to john that I agree", ConversationContext(recentPeople: ["Sarah"]))
        #expect(try d.outcome.get().action == .createDraft(recipient: "john", content: "I agree"))
        let app = await route("open mail", ConversationContext(activeApp: .notes))
        #expect(try app.outcome.get().action == .activateApp(.mail))
    }

    @Test func thatWindowUsesContextAppOrActiveWindow() async throws {
        #expect(try await route("put that window on the left", ConversationContext(activeApp: .safari)).outcome.get().action
            == .moveWindow(.app(.safari), .leftHalf))
        #expect(try await route("maximize it").outcome.get().action == .moveWindow(.active, .maximize))
    }

    @Test func moveWithoutDestinationAsks() async throws {
        let d = await route("move that over there")
        #expect(try d.outcome.get().kind == .clarification)
        #expect(d.pending == .position(window: .active))
    }

    @Test func changeThatUsesLastEditedText() async throws {
        let d = await route("change that to 4 pm", ConversationContext(lastEditedText: "3 pm"))
        #expect(try d.outcome.get().action == .replaceText(old: "3 pm", new: "4 pm"))
        #expect(try await route("change that to 4 pm").outcome.get().kind == .clarification)
    }

    @Test func sendToSomeoneElseIsNotGuessed() async throws {
        #expect(try await route("send it to him", ConversationContext(recentPeople: ["Sam"])).outcome.get().kind == .clarification)
    }

    @Test(arguments: ["close it", "delete that", "remove this", "quit safari"])
    func missingActionsAreDeclined(utterance: String) async throws {
        let model = FakeModel()
        let d = await route(utterance, model: model)
        #expect(try d.outcome.get().kind == .unsupported)
        #expect(model.calls.isEmpty)
    }
}

@Suite("Follow-up answers complete the pending action")
struct FollowUpTests {
    @Test func whichAppAnswer() async throws {
        let router = IntentRouter(model: FakeModel())
        _ = await router.route("open it")
        let d = await router.route("Notes.")
        #expect(d.stage == .followUp)
        #expect(try d.outcome.get().action == .activateApp(.notes))
        #expect(await router.context.pending == nil)
    }

    @Test func whichPersonAnswerByNameOrNumber() async throws {
        let ctx = ConversationContext(recentPeople: ["Sarah", "Sam"], updatedAt: Date())
        let byName = IntentRouter(model: FakeModel(), context: ctx)
        _ = await byName.route("reply to her saying on my way")
        #expect(try await byName.route("Sam").outcome.get().action == .createDraft(recipient: "Sam", content: "on my way"))

        let byNumber = IntentRouter(model: FakeModel(), context: ctx)
        _ = await byNumber.route("reply to her")
        #expect(try await byNumber.route("the first one").outcome.get().action == .createDraft(recipient: "Sarah", content: ""))
    }

    @Test func positionAnswer() async throws {
        let router = IntentRouter(model: FakeModel())
        _ = await router.route("move it")
        #expect(try await router.route("left half").outcome.get().action == .moveWindow(.active, .leftHalf))
    }

    @Test func unrelatedCommandDropsThePendingQuestion() async throws {
        let router = IntentRouter(model: FakeModel())
        _ = await router.route("open it")
        let d = await router.route("scroll down")
        #expect(try d.outcome.get().action == .scroll(.down))
        #expect(await router.context.pending == nil)
    }
}

@Suite("Guards on model output")
struct GuardTests {
    @Test func leakedExampleTimeIsNotRouted() async throws {
        let model = FakeModel(["when am i seeing the dentist on friday": .success(modelIntent(.queryCalendar(timeExpression: "tomorrow 4 pm")))])
        let d = await route("when am I seeing the dentist on friday", model: model)
        #expect(try d.outcome.get().kind == .clarification)
        #expect(d.stage == .guarded)
    }

    @Test func droppedTimeWordIsNotRouted() async throws {
        let model = FakeModel(["is anything booked at four tomorrow": .success(modelIntent(.queryCalendar(timeExpression: "tomorrow")))])
        let d = await route("is anything booked at four tomorrow", model: model)
        #expect(try d.outcome.get().kind == .clarification)
    }

    @Test func groundedModelAnswerPasses() async throws {
        let model = FakeModel(["when am i seeing the dentist on friday": .success(modelIntent(.queryCalendar(timeExpression: "friday")))])
        let d = await route("when am I seeing the dentist on friday", model: model)
        #expect(try d.outcome.get().action == .queryCalendar(timeExpression: "friday"))
        #expect(d.stage == .model)
    }

    @Test func guessedAppIsNotRouted() async throws {
        let model = FakeModel(["bring up the thing i was using": .success(modelIntent(.activateApp(.safari)))])
        let d = await route("bring up the thing I was using", model: model)
        #expect(try d.outcome.get().kind == .clarification)
    }

    @Test func mailWordsNeverBecomeACalendarAnswer() async throws {
        let model = FakeModel(["where's that email sarah sent": .success(modelIntent(.queryCalendar(timeExpression: "sarah")))])
        let d = await route("where's that email sarah sent", model: model)
        #expect(try d.outcome.get().kind == .clarification)
    }

    @Test func sendRequiresTheWordSend() async throws {
        let model = FakeModel(["ship the note to sarah": .success(modelIntent(.requestSend))])
        #expect(try await route("ship the note to sarah", model: model).outcome.get().kind == .clarification)
    }

    @Test func paraphrasedDraftContentIsRejected() async throws {
        let model = FakeModel(["get a note to priya about lunch": .success(
            modelIntent(.createDraft(recipient: "priya", content: "Want to grab lunch tomorrow?"), kind: .task))])
        #expect(try await route("could you get a note to priya about lunch", model: model).outcome.get().kind == .clarification)
    }

    @Test func emptyModelSlotBecomesATargetedQuestion() async throws {
        let raw = #"{"kind":"direct","action":"read_message","target":"","detail":"","summary":"s"}"#
        let model = FakeModel(["dig up that thing": .failure(.schemaViolation("“target” is empty"))], raw: ["dig up that thing": raw])
        let d = await route("dig up that thing", model: model)
        #expect(try d.outcome.get().summary == "Which email should I look for?")
    }

    @Test func transportErrorsStayErrors() async {
        let model = FakeModel(["tidy up my desktop": .failure(.serverUnavailable("down"))])
        let d = await route("tidy up my desktop", model: model)
        #expect(throws: ClassificationError.serverUnavailable("down")) { try d.outcome.get() }
    }
}

@Suite("Task context")
struct ContextTests {
    @Test func recordsProposedActions() {
        var c = ConversationContext()
        let t = Date()
        c.record(.readMessage(query: "email from Priya about the invoice"), now: t)
        #expect(c.recentPeople == ["Priya"])
        #expect(c.activeApp == .mail)
        c.record(.createDraft(recipient: "Marco", content: ""), now: t)
        #expect(c.recentPeople == ["Marco", "Priya"])
        #expect(c.hasDraft)
        c.record(.requestSend, now: t)
        #expect(!c.hasDraft)
        c.record(.tileWindows(left: .mail, right: .calendar), now: t)
        #expect(c.activeApp == nil)
    }

    @Test func staleContextIsIgnored() async throws {
        let old = ConversationContext(activeApp: .notes, updatedAt: Date(timeIntervalSinceNow: -3600))
        let router = IntentRouter(model: FakeModel(), context: old, contextTTL: 600)
        #expect(try await router.route("open it").outcome.get().kind == .clarification)
    }

    @Test func peopleListIsBounded() {
        var c = ConversationContext()
        for n in ["A1", "B2", "C3", "D4", "b2"] { c.notePerson(n) }
        #expect(c.recentPeople == ["b2", "D4", "C3"])
    }

    @Test func conversationFlow() async throws {
        let router = IntentRouter(model: FakeModel())
        _ = await router.route("find the email from Priya about the invoice")
        #expect(try await router.route("reply to her saying it's paid").outcome.get().action
            == .createDraft(recipient: "Priya", content: "it's paid"))
        #expect(try await router.route("send it").outcome.get().action == .requestSend)
    }
}

@Suite("Cleaner")
struct CleanerTests {
    @Test(arguments: [
        ("Flow, open notes.", "open notes"),
        ("Could you please scroll down?", "scroll down"),
        ("uh, open, um, mail", "open, mail"),
        ("open safari please", "open safari"),
        ("  Reply to Sarah: Thanks!  ", "Reply to Sarah: Thanks"),
    ])
    func cleans(raw: String, expected: String) {
        #expect(Cleaner.clean(raw) == expected)
    }
}

@Suite("ASR robustness (cases taken from real Argmax transcripts)")
struct ASRRobustnessTests {
    @Test func amPmWithDotsIsNormalized() async throws {
        #expect(try await route("Replace 2 p.m. with 2.30 p.m.").outcome.get().action == .replaceText(old: "2 pm", new: "2:30 pm"))
        #expect(try await route("Change that to 4 p.m.", ConversationContext(lastEditedText: "3 pm")).outcome.get().action
            == .replaceText(old: "3 pm", new: "4 pm"))
        #expect(try await route("Am I busy at 10 a.m. tomorrow?").outcome.get().action == .queryCalendar(timeExpression: "at 10 am tomorrow"))
    }

    @Test func colonlessTimeIsConfirmedNotGuessed() async throws {
        let d = await route("Change 3 to 330.")
        let q = try d.outcome.get()
        #expect(q.kind == .clarification)
        #expect(q.summary.contains("3:30"))
        #expect(d.pending == .confirm(proposed: .replaceText(old: "3", new: "3:30"), otherwise: .replaceText(old: "3", new: "330"), kind: .edit))
    }

    @Test func confirmationAnswers() async throws {
        let yes = IntentRouter(model: FakeModel())
        _ = await yes.route("Send an email to Marco that the meeting moved to 345.")
        #expect(try await yes.route("Yes.").outcome.get().action == .createDraft(recipient: "Marco", content: "the meeting moved to 3:45"))
        let no = IntentRouter(model: FakeModel())
        _ = await no.route("Send an email to Marco that the meeting moved to 3.45.")
        #expect(try await no.route("no, keep it").outcome.get().action == .createDraft(recipient: "Marco", content: "the meeting moved to 3.45"))
    }

    @Test(arguments: ["room 2026 is free", "see you on the 12th", "it costs 3:30", "the Q3 report"])
    func numbersThatAreNotColonlessTimesPass(text: String) {
        #expect(Guard.proposeTime(text) == nil)
    }

    @Test func maleIsMailInAppPositionsOnly() async throws {
        #expect(try await route("Make the male window bigger.").outcome.get().action == .resizeWindow(.app(.mail), .larger))
        #expect(try await route("Maximize the male window").outcome.get().action == .moveWindow(.app(.mail), .maximize))
        // Dictated content is never rewritten.
        #expect(try await route("tell Sam the male nurse called").outcome.get().action
            == .createDraft(recipient: "Sam", content: "the male nurse called"))
    }

    @Test func andHeardAsEndBetweenApps() async throws {
        #expect(try await route("Put notes on the left end safari on the right.").outcome.get().action
            == .tileWindows(left: .notes, right: .safari))
    }

    @Test func sizeAndPositionWordsMustBeSpoken() async throws {
        let model = FakeModel(["maximize ige": .success(modelIntent(.resizeWindow(.active, .larger)))])
        #expect(try await route("Maximize Ige", model: model).outcome.get().kind == .clarification)
    }

    @Test func searchNeedsASearchVerb() async throws {
        let model = FakeModel(["emailed them that friday works": .success(modelIntent(.readMessage(query: "Friday works")))])
        #expect(try await route("Emailed them that Friday works.", model: model).outcome.get().kind == .clarification)
    }

    @Test func recipientMustLookLikeAName() async throws {
        let model = FakeModel(["signed the d email": .success(modelIntent(.createDraft(recipient: "D email", content: ""), kind: .task))])
        #expect(try await route("Signed the D email.", model: model).outcome.get().kind == .clarification)
    }
}

@Suite("Fixes after unseen-voice validation (unit-tested only)")
struct PostValidationFixTests {
    @Test func pronounInModelSlotAsks() async throws {
        let model = FakeModel(["find her lost email": .success(modelIntent(.readMessage(query: "her lost email")))])
        #expect(try await route("Find her lost email.", model: model).outcome.get().kind == .clarification)
    }

    @Test func pronounRecipientFromModelAsks() async throws {
        let model = FakeModel(["send the to them": .success(modelIntent(.createDraft(recipient: "them", content: ""), kind: .task))])
        #expect(try await route("Send the to them.", model: model).outcome.get().kind == .clarification)
    }

    @Test func calendarSlotNeedsATimeWord() async throws {
        let model = FakeModel(["go to calendar me": .success(modelIntent(.queryCalendar(timeExpression: "calendar")))])
        #expect(try await route("Go to calendar me.", model: model).outcome.get().kind == .clarification)
    }

    @Test func nameNeverKeepsASentencePeriod() async throws {
        #expect(try await route("Reply to Sarah. Thanks, see you at four.").outcome.get().action
            == .createDraft(recipient: "Sarah", content: "Thanks, see you at four"))
        #expect(try await route("email J.R. saying hi").outcome.get().action == .createDraft(recipient: "J.R", content: "hi"))
    }

    @Test func scrollDirectionMustBeSpoken() async throws {
        let model = FakeModel(["scroll after bit": .success(modelIntent(.scroll(.down)))])
        #expect(try await route("Scroll after bit.", model: model).outcome.get().kind == .clarification)
    }
}

@Suite("Compatibility with FlowAX (Track A ADR 0003)")
struct FlowAXCompatibilityTests {
    @Test(arguments: [
        ("click the second Reply button", "the second Reply button"),
        ("press the archive button", "the archive button"),
        ("click on forward", "forward"),
        ("tap the Save button", "the Save button"),
    ])
    func clickLabelsKeepArticlesOrdinalsAndRoleWords(utterance: String, label: String) async throws {
        #expect(try await route(utterance).outcome.get().action == .clickElement(label: label))
    }

    @Test func focusKeepsTheRoleWord() async throws {
        #expect(try await route("focus the search field").outcome.get().action == .focus(label: "the search field"))
        #expect(try await route("put the cursor in the subject field").outcome.get().action == .focus(label: "the subject field"))
    }

    @Test(arguments: ["show numbers", "show numbers for buttons", "numbers", "hide numbers", "choose 3", "pick two", "number 4", "3", "seven"])
    func overlayPhrasesNeverReachTheModel(utterance: String) async throws {
        let model = FakeModel()
        let d = await route(utterance, model: model)
        #expect(d.stage == .overlay)
        #expect(try d.outcome.get().action == nil)
        #expect(model.calls.isEmpty)
    }

    @Test func pendingQuestionAnswerBeatsOverlayNumber() async throws {
        let router = IntentRouter(model: FakeModel(), context: ConversationContext(recentPeople: ["Sarah", "Sam"], updatedAt: Date()))
        _ = await router.route("reply to her")
        let d = await router.route("2")
        #expect(d.stage == .followUp)
        #expect(try d.outcome.get().action == .createDraft(recipient: "Sam", content: ""))
    }

    @Test(arguments: ["click the Send button", "press send", "hit send now"])
    func spokenSendClickUsesTheConfirmationFlow(utterance: String) async throws {
        #expect(try await route(utterance).outcome.get().action == .requestSend)
    }

    @Test func modelClickOnSendIsRedirected() async throws {
        let model = FakeModel(["finish it off with the send key": .success(modelIntent(.clickElement(label: "Send")))])
        #expect(try await route("finish it off with the send key", model: model).outcome.get().action == .requestSend)
    }

    @Test(arguments: ["click delete", "press the trash button", "click discard draft"])
    func destructiveClicksAreDeclined(utterance: String) async throws {
        #expect(try await route(utterance).outcome.get().kind == .unsupported)
    }
}

@Suite("Replies to the open message and draft review references")
struct OpenMessageReferenceTests {
    @Test func namelessReplyUsesTheSinglePersonInContext() async throws {
        let ctx = ConversationContext(recentPeople: ["Sarah"], openMessage: "Meeting tomorrow")
        #expect(try await route("draft a reply saying I can meet at 3", ctx).outcome.get().action
            == .createDraft(recipient: "Sarah", content: "I can meet at 3"))
        #expect(try await route("reply saying sounds good", ctx).outcome.get().action
            == .createDraft(recipient: "Sarah", content: "sounds good"))
    }

    @Test func namedReplyIsNotTreatedAsAReplyToTheOpenMessage() async throws {
        let ctx = ConversationContext(recentPeople: ["Sarah"])
        #expect(try await route("reply to john that I agree", ctx).outcome.get().action
            == .createDraft(recipient: "john", content: "I agree"))
    }

    @Test func namelessReplyWithoutContextAsks() async throws {
        #expect(try await route("draft a reply saying ok").outcome.get().kind == .clarification)
    }

    @Test func showItToMeReviewsOnlyWhenADraftExists() async throws {
        #expect(try await route("show it to me", ConversationContext(hasDraft: true)).outcome.get().action == .requestReview)
        #expect(try await route("show it to me").outcome.get().kind == .clarification)
    }
}
