import FlowAudio
import FlowCore
@testable import FlowPlanner
import FlowRouting
@testable import FlowSession
@testable import FlowSpeech
import Foundation
import Testing

@Suite("Acceptance: spoken voice session (mock executor)", .serialized)
struct SpokenSessionAcceptanceTests {
    @Test func whichSarahIsSpokenAndAnsweredByVoice() async throws {
        let h = await SpeechHarness()
        await h.listen()

        h.transcriber.say("Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.")
        #expect(await h.waitForSpeech { $0.hasPrefix("Which Sarah?") })
        let question = try #require(await h.said.first { $0.hasPrefix("Which Sarah?") })
        #expect(question.contains("Sarah Chen") && question.contains("Sarah Okafor"))
        #expect(!question.contains("[FlowTest]"))  // tags are not read aloud

        await h.waitUntilQuiet()
        h.transcriber.say("Sarah Chen")
        #expect(await h.waitForSpeech { $0.contains("Here's the draft") })
        #expect(await h.state.isCompletedState)
        #expect(await h.mock.world.sent.isEmpty)
        await h.coordinator.stopListening()
    }

    @Test func importantFailuresAreAnnounced() async throws {
        let h = await SpeechHarness()
        await h.mock.inject([ExecutionResult(status: .failed, error: .permissionDenied, userMessage: "Flow can't control Notes yet.")],
                            for: .activate)
        await h.coordinator.submit("open notes")
        #expect(await h.waitForSpeech { $0 == "Flow can't control Notes yet." })
        #expect(await h.feedback.spoken.last?.kind == .failure)
    }

    @Test func routineLowRiskSuccessIsNotNarrated() async throws {
        let h = await SpeechHarness()
        await h.coordinator.submit("open notes")
        await h.coordinator.submit("scroll down")
        try await Task.sleep(for: .milliseconds(150))
        #expect(await h.said.isEmpty)
        #expect(await h.mock.world.activeApp == .notes)  // it still happened, visibly
    }

    @Test func flowStopInterruptsSpeechAndTheTask() async throws {
        let h = await SpeechHarness(speech: RecordingSpeech(duration: .seconds(3)))
        await h.listen()
        h.transcriber.say("Find Sarah's email about tomorrow")
        #expect(await h.waitForSpeech { $0.hasPrefix("Which Sarah?") })
        h.transcriber.say("Flow, stop")
        #expect(await eventually { await h.speech.interrupted.contains { $0.hasPrefix("Which Sarah?") } })
        #expect(await eventually { await h.state.isCancelledState })
        await h.coordinator.stopListening()
    }
}

@Suite("Echo: Flow never obeys its own voice", .serialized)
struct EchoSuppressionTests {
    @Test func ownPromptHeardWhileSpeakingIsDropped() async throws {
        let h = await SpeechHarness(speech: RecordingSpeech(duration: .milliseconds(800)))
        await h.listen()
        h.transcriber.say("Find Sarah's email about tomorrow")
        #expect(await h.waitForSpeech { $0.hasPrefix("Which Sarah?") })
        let turnsBefore = await h.coordinator.turns.count
        // The microphone picks up Flow's own question, including a candidate's name.
        h.transcriber.say("Which Sarah? Sarah Chen, Meeting tomorrow")
        try await Task.sleep(for: .milliseconds(200))
        #expect(await h.coordinator.turns.count == turnsBefore)
        #expect(await h.state.choiceQuestion != nil)  // still waiting for the *user*
        await h.coordinator.stopListening()
    }

    @Test func plainStopInsideFlowsOwnSentenceIsIgnoredButFlowStopWorks() {
        var g = EchoGuard(tail: 0.5, partialLatency: 0.1)
        let t0 = Date()
        g.speechStarted("To end, say stop.", at: t0)
        let during = t0.addingTimeInterval(0.4)
        #expect(g.decide("stop", heardFrom: t0.addingTimeInterval(0.2), finalizedAt: during) == .reject(.ownSpeech))
        #expect(g.decide("Flow, stop", heardFrom: t0.addingTimeInterval(0.2), finalizedAt: during) == .acceptAndInterrupt)
        #expect(g.decide("cancel", heardFrom: t0.addingTimeInterval(0.2), finalizedAt: during) == .acceptAndInterrupt)
    }

    @Test func otherSpeechDuringFlowsSentenceIsDroppedHalfDuplex() {
        var g = EchoGuard()
        let t0 = Date()
        g.speechStarted("Which Sarah? Sarah Chen, Meeting tomorrow; or Sarah Okafor, Lunch.", at: t0)
        #expect(g.decide("the first one", heardFrom: t0.addingTimeInterval(1), finalizedAt: t0.addingTimeInterval(2))
            == .reject(.spokeDuringPrompt))
    }

    @Test func answerStartedAfterFlowFinishedIsAcceptedEvenIfItRepeatsFlowsWords() {
        var g = EchoGuard()
        let t0 = Date()
        g.speechStarted("Which Sarah? Sarah Chen, or Sarah Okafor.", at: t0)
        g.speechEnded(at: t0.addingTimeInterval(3))
        #expect(g.decide("Sarah Chen", heardFrom: t0.addingTimeInterval(3.6), finalizedAt: t0.addingTimeInterval(4.8)) == .accept)
    }

    @Test func echoArrivingJustAfterSpeechWithoutTimingIsDropped() {
        var g = EchoGuard()
        let t0 = Date()
        g.speechStarted("Here's the draft. Say send it when you're ready.", at: t0)
        g.speechEnded(at: t0.addingTimeInterval(2.5))
        // Unknown start time; the words are Flow's.
        #expect(g.decide("say send it when you're ready", heardFrom: nil, finalizedAt: t0.addingTimeInterval(3)) == .reject(.ownSpeech))
        // Long after the tail: a real command.
        #expect(g.decide("send it", heardFrom: nil, finalizedAt: t0.addingTimeInterval(9)) == .accept)
    }
}

@Suite("Confirmation dialogue and timeouts", .serialized)
struct ConfirmationDialogueTests {
    /// Typed path to "awaiting confirmation" for a reviewed reply to Sarah Chen.
    func readyToConfirm(_ h: SpeechHarness) async {
        await h.coordinator.submit("Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.")
        await h.coordinator.submit("Sarah Chen")
        await h.coordinator.submit("send it")
    }

    @Test func confirmationIsSpokenWithRecipientAndContentAndNoSendsNothing() async throws {
        let h = await SpeechHarness()
        await readyToConfirm(h)
        #expect(await h.waitForSpeech { $0.hasPrefix("Send this email to sarah.chen@example.invalid?") && $0.contains("I can meet at 3") })
        await h.coordinator.submit("no")
        #expect(await h.waitForSpeech { $0.contains("won't send") })
        #expect(await h.mock.sendRequests.isEmpty)
    }

    @Test func unansweredConfirmationIsRemindedThenCancelledNeverSent() async throws {
        let h = await SpeechHarness(timing: FeedbackTiming(reminderAfter: .milliseconds(150), confirmationTimeout: .milliseconds(400),
                                                           idleListeningTimeout: .seconds(60)))
        await readyToConfirm(h)
        #expect(await h.waitForSpeech { $0.hasPrefix("Still waiting. Should I send it?") })
        #expect(await h.waitForSpeech { $0 == "I didn't hear an answer, so I didn't send it." })
        #expect(await h.state.isCancelledState)
        #expect(await h.mock.sendRequests.isEmpty)
    }

    @Test func unansweredChoiceIsRemindedOnceAndStaysOpen() async throws {
        let h = await SpeechHarness(timing: FeedbackTiming(reminderAfter: .milliseconds(150), confirmationTimeout: .milliseconds(300),
                                                           idleListeningTimeout: .seconds(60)))
        await h.coordinator.submit("Find Sarah's email about tomorrow")
        #expect(await h.waitForSpeech { $0 == "Still waiting. Which Sarah?" })
        try await Task.sleep(for: .milliseconds(400))
        #expect(await h.state.choiceQuestion != nil)  // a choice is never auto-cancelled
        #expect(await h.said.filter { $0.hasPrefix("Still waiting") }.count == 1)
    }
}

@Suite("Session states, interruptions and degraded output", .serialized)
struct SessionStateTests {
    @Test func idleListeningTimesOutAndSaysSo() async throws {
        let h = await SpeechHarness(timing: FeedbackTiming(reminderAfter: .seconds(60), confirmationTimeout: .seconds(60),
                                                           idleListeningTimeout: .milliseconds(200)))
        await h.listen()
        #expect(await eventually { await !h.coordinator.isListening })
        #expect(await h.waitForSpeech { $0.hasPrefix("I've stopped listening.") })
    }

    @Test func microphoneFailureIsAnnounced() async throws {
        let h = await SpeechHarness()
        await h.listen()
        h.transcriber.fail(.engineFailed("device disconnected"))
        #expect(await h.waitForSpeech { $0.hasPrefix("I stopped listening.") })
        #expect(await eventually { await !h.coordinator.isListening })
    }

    @Test func unavailableVoiceDegradesToVisualOnly() async throws {
        let h = await SpeechHarness(speech: RecordingSpeech(available: false))
        guard case .unavailable = await h.feedback.status else { Issue.record("expected unavailable"); return }
        await h.coordinator.submit("Find Sarah's email about tomorrow")
        #expect(await eventually { await h.feedback.spoken.contains { $0.text.hasPrefix("Which Sarah?") } })
        #expect(await h.said.isEmpty)
        // The session itself is unaffected: the question is on screen.
        guard case .awaitingChoice = await h.coordinator.status.task else { Issue.record("no visual question"); return }
    }

    @Test func mutedFeedbackSpeaksNothingButStillLogs() async throws {
        let h = await SpeechHarness()
        await h.feedback.setMuted(true)
        await h.coordinator.submit("Find Sarah's email about tomorrow")
        #expect(await eventually { await h.feedback.spoken.contains { $0.kind == .question } })
        #expect(await h.said.isEmpty)
    }

    @Test func newerFeedbackReplacesOlderSpeech() async throws {
        let h = await SpeechHarness(speech: RecordingSpeech(duration: .seconds(2)))
        await h.mock.inject([ExecutionResult(status: .failed, error: .unknown, userMessage: "First failure.")], for: .activate)
        await h.mock.inject([ExecutionResult(status: .failed, error: .unknown, userMessage: "Second failure.")], for: .scroll)
        await h.coordinator.submit("open notes")
        #expect(await h.waitForSpeech { $0 == "First failure." })
        await h.coordinator.submit("scroll down")
        #expect(await h.waitForSpeech { $0 == "Second failure." })
        #expect(await h.speech.interrupted.contains("First failure."))
    }

    @Test func typedStopAlsoStopsSpeech() async throws {
        let h = await SpeechHarness(speech: RecordingSpeech(duration: .seconds(3)))
        await h.coordinator.submit("Find Sarah's email about tomorrow")
        #expect(await h.waitForSpeech { $0.hasPrefix("Which Sarah?") })
        await h.coordinator.submit("stop")
        #expect(await eventually { await h.speech.interrupted.contains { $0.hasPrefix("Which Sarah?") } })
    }

    @Test func detachRestoresTheUnhookedCoordinator() async throws {
        let h = await SpeechHarness()
        await h.feedback.detach()
        await h.coordinator.submit("Find Sarah's email about tomorrow")
        try await Task.sleep(for: .milliseconds(150))
        #expect(await h.said.isEmpty)
        #expect(await h.state.choiceQuestion != nil)
    }
}

@Suite("Feedback policy (pure)")
struct FeedbackPolicyTests {
    func turn(_ state: RunState, say: [String] = [], plan: String? = "plan") -> SessionTurn {
        SessionTurn(id: UUID(), utterance: "u", source: .typed, say: say, state: state, planSummary: plan, runEvents: [],
                    duration: .zero)
    }

    func question(_ senders: [String]) -> PlanQuestion {
        let refs = senders.enumerated().map { MessageRef(id: "m\($0.offset)", sender: $0.element, subject: "[FlowTest] Topic \($0.offset)") }
        return PlanQuestion(stepID: 1, prompt: "I found …. Which one?", options: [], candidates: refs, askedAt: Date())
    }

    @Test func sharedFirstNameBecomesWhichName() {
        let text = FeedbackPolicy.spokenChoice(question(["Sarah Chen", "Sarah Okafor"]))
        #expect(text == "Which Sarah? Sarah Chen, Topic 0; or Sarah Okafor, Topic 1.")
    }

    @Test func differentNamesAskWhichOne() {
        #expect(FeedbackPolicy.spokenChoice(question(["Sarah Chen", "Priya Patel"])).hasPrefix("Which one?"))
    }

    @Test func longListsAreShortened() {
        let text = FeedbackPolicy.spokenChoice(question(["Lee A", "Lee B", "Lee C", "Lee D", "Lee E"]))
        #expect(text.contains("and 2 more"))
        #expect(!text.contains("Lee D"))
    }

    @Test func confirmationNamesRecipientAndBody() {
        let draft = DraftSnapshot(channel: .whatsapp, id: "d", recipients: ["+1 555 0100"], body: "see you soon", version: 1)
        let text = FeedbackPolicy.spokenConfirmation(ApprovalRequest(stepID: 0, action: .send, draft: draft, prompt: ""))
        #expect(text == "Send this whatsapp to +1 555 0100? It says: see you soon. Say yes to send it, or no.")
        #expect(!text.lowercased().contains("cancel") && !text.lowercased().contains("stop"))  // never echoes a control word
    }

    @Test func silentRoutineVerboseDone() {
        let done = turn(.completed(planID: UUID()))
        #expect(FeedbackPolicy().cue(for: done, phase: .finished("")) == nil)
        #expect(FeedbackPolicy(verbosity: .verbose).cue(for: done, phase: .finished(""))?.text == "Done.")
    }

    @Test func minimalKeepsOnlyQuestionsConfirmationsAndFailures() {
        let p = FeedbackPolicy(verbosity: .minimal)
        #expect(p.cue(for: turn(.completed(planID: UUID()), say: ["Here's the draft."]), phase: .finished("")) == nil)
        #expect(p.cue(for: turn(.stopped(planID: UUID(), reason: "It failed.")), phase: .finished(""))?.kind == .failure)
        #expect(p.cue(for: turn(.awaitingChoice(question(["A B", "A C"]))), phase: .idle)?.kind == .question)
    }

    @Test func routerQuestionIsSpokenAsAQuestion() {
        let cue = FeedbackPolicy().cue(for: turn(.idle, say: ["Which app: Mail, Calendar, Notes, Finder or Safari?"], plan: nil),
                                       phase: .awaitingAnswer("Which app?"))
        #expect(cue?.kind == .question)
    }

    @Test func listenFailureIsSpokenOnce() {
        let p = FeedbackPolicy()
        #expect(p.cue(forListenChange: .listening, .failed("Speech recognition stopped unexpectedly."))?.kind == .failure)
        #expect(p.cue(forListenChange: .failed("x"), .failed("y")) == nil)
    }
}

extension RunState {
    var isCompletedState: Bool { if case .completed = self { true } else { false } }
    var isCancelledState: Bool { if case .cancelled = self { true } else { false } }
    var choiceQuestion: PlanQuestion? { if case .awaitingChoice(let q) = self { q } else { nil } }
}
