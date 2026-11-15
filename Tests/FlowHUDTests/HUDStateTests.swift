import CoreGraphics
import FlowCore
@testable import FlowHUD
@testable import FlowPlanner
import FlowRouting
@testable import FlowSession
import FlowSpeech
import Foundation
import Testing

func turn(_ utterance: String, _ state: RunState, say: [String] = [], source: TurnSource = .voice, plan: String? = nil) -> SessionTurn {
    SessionTurn(id: UUID(), utterance: utterance, source: source, say: say, state: state, planSummary: plan, runEvents: [],
                duration: .milliseconds(10))
}

func status(_ listen: ListenStatus, _ task: TaskPhase) -> HUDState.Input {
    .coordinator(.status(CoordinatorStatus(listen: listen, task: task)))
}

@Suite("HUD state from voice-session events")
struct HUDStateTests {
    @Test func listeningHearingProcessingIdle() {
        var s = HUDState()
        #expect(s.activity == .idle && !s.listening)
        s.apply(status(.starting, .idle)); #expect(s.activity == .listening)
        s.apply(status(.hearing("open no"), .idle)); #expect(s.activity == .hearing && s.hearing == "open no")
        s.apply(.coordinator(.finalized("Open Notes.")))
        #expect(s.lastHeard == "Open Notes." && s.hearing == nil)
        s.apply(status(.listening, .working("Open Notes."))); #expect(s.activity == .processing)
        s.apply(.coordinator(.turn(turn("Open Notes.", .completed(planID: UUID()), plan: "Open Notes"))))
        s.apply(status(.listening, .finished(""))); #expect(s.activity == .listening)
        #expect(s.outcome == HUDOutcome(kind: .verified, text: "Done: Open Notes."))
        s.apply(status(.off, .finished(""))); #expect(s.activity == .idle)
    }

    @Test func numberedChoicesAndQuestionAreShown() {
        var s = HUDState()
        let prompt = "I found 3 messages: 1. Sarah Chen — “Meeting tomorrow”; 2. Sarah Okafor — “Lunch”; 3. Sarah Chen — “Launch”. Which one?"
        let options = ["1. Sarah Chen — “Meeting tomorrow”", "2. Sarah Okafor — “Lunch”", "3. Sarah Chen — “Launch”"]
        s.apply(.coordinator(.turn(turn("Find Sarah's email", .awaitingChoice(PlanQuestion(stepID: 1, prompt: prompt, options: options, candidates: [], askedAt: Date())), say: [prompt]))))
        s.apply(status(.listening, .awaitingChoice(prompt: prompt, options: options)))
        #expect(s.activity == .awaitingChoice && s.expectsResponse)
        #expect(s.question == "Which one?")
        #expect(s.choices.map(\.number) == [1, 2, 3])
        #expect(s.choices[1].text == "Sarah Okafor — “Lunch”")
        #expect(s.hint.contains("number"))
        #expect(s.outcome == nil, "the question is shown as a question, not as an outcome")
    }

    @Test func confirmationIsShownButNeverApprovedByTheHUD() {
        var s = HUDState()
        let prompt = "Ready to send this email to sarah.chen@example.invalid. It says: “I can meet at 3:30”. Say “yes, send it” to send, or “no”."
        s.apply(status(.listening, .awaitingConfirmation(prompt)))
        #expect(s.activity == .awaitingConfirmation && s.isConfirmation)
        #expect(s.question == prompt)
        #expect(s.hint.contains("yes, send it") && s.hint.contains("Nothing is sent"))
        // HUDState has no input that answers a question: only the session can.
        s.apply(.setCollapsed(true)); s.apply(.setHidden(true))
        #expect(s.isConfirmation)
    }

    @Test func aNewQuestionReShowsAndExpandsAHiddenHUD() {
        var s = HUDState()
        s.apply(.setHidden(true)); s.apply(.setCollapsed(true))
        s.apply(status(.listening, .awaitingAnswer("Which app?")))
        #expect(!s.hidden && !s.collapsed)
        // The user may collapse it again while the same question is open.
        s.apply(.setCollapsed(true))
        s.apply(status(.hearing("no"), .awaitingAnswer("Which app?")))
        #expect(s.collapsed)
    }

    @Test func dismissingDoesNotChangeTheTask() {
        var s = HUDState()
        s.apply(status(.listening, .working("find sarah's email")))
        s.apply(.setHidden(true))
        #expect(s.hidden && s.activity == .processing && s.listening)
    }

    @Test func speakingAndExpectedResponseAreBothVisible() {
        var s = HUDState()
        s.apply(status(.listening, .awaitingAnswer("Which app?")))
        s.apply(.feedback(.status(.speaking("Which app?"))))
        #expect(s.activity == .speaking && s.expectsResponse)
        #expect(s.hint.contains("Answer when Flow finishes"))
        s.apply(.feedback(.status(.ready)))
        #expect(s.activity == .awaitingAnswer)
    }

    @Test func failuresAndCancellationsAreLabelled() {
        var s = HUDState()
        s.apply(.coordinator(.turn(turn("close the mail window", .stopped(planID: UUID(), reason: "Mail has no matching window.")))))
        #expect(s.outcome == HUDOutcome(kind: .notDone, text: "Mail has no matching window."))
        s.apply(.coordinator(.turn(turn("stop", .cancelled(planID: nil), say: ["Stopped."]))))
        #expect(s.outcome?.kind == .cancelled)
        #expect(s.recent.map(\.result) == [.cancelled, .notDone])
    }

    @Test func microphoneFailureIsAnError() {
        var s = HUDState()
        s.apply(status(.failed("The microphone was disconnected."), .idle))
        #expect(s.activity == .error && s.errorMessage == "The microphone was disconnected.")
    }

    @Test func confirmationTimeoutIsExplained() {
        var s = HUDState()
        s.apply(.feedback(.timedOut("confirmation")))
        #expect(s.outcome == HUDOutcome(kind: .cancelled, text: "No answer, so nothing was sent."))
    }

    @Test func ignoredEchoIsShown() {
        var s = HUDState()
        s.apply(.feedback(.ignored(utterance: "Which app?", reason: .ownSpeech)))
        #expect(s.ignored == "Which app?")
    }

    @Test func retentionIsBoundedAndTruncated() {
        var s = HUDState()
        let long = String(repeating: "secret body text ", count: 50)
        for i in 0..<10 { s.apply(.coordinator(.turn(turn("command \(i)", .completed(planID: UUID()), say: [long])))) }
        #expect(s.recent.count == HUDState.maxRecent)
        #expect(s.recent.allSatisfy { $0.summary.count <= HUDState.maxRecentLength })
        #expect((s.outcome?.text.count ?? 0) <= HUDState.maxOutcomeLength)
        #expect(s.recent.first?.heard == "command 9")
    }

    @Test func voiceUnavailableIsNoted() {
        var s = HUDState()
        s.apply(.feedback(.status(.unavailable("No speech voice is installed."))))
        #expect(s.voiceNote?.contains("No speech voice") == true)
    }
}

@Suite("HUD placement")
struct HUDPlacementTests {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 875)       // visible frame, menu bar excluded
    let right = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
    let size = CGSize(width: 340, height: 180)

    @Test func defaultsToTheTopRightOfThePrimaryDisplay() {
        let f = HUDPlacement.frame(size: size, screens: [main, right], saved: nil)
        #expect(f.maxX == main.maxX - HUDPlacement.margin && f.maxY == main.maxY - HUDPlacement.margin)
    }

    @Test func savedPositionOnASecondDisplayIsKept() {
        let f = HUDPlacement.frame(size: size, screens: [main, right], saved: CGPoint(x: 2000, y: 300))
        #expect(f.origin == CGPoint(x: 2000, y: 300))
    }

    @Test func positionIsClampedInsideTheDisplay() {
        let f = HUDPlacement.frame(size: size, screens: [main], saved: CGPoint(x: 1300, y: 800))
        #expect(main.contains(f))
    }

    @Test func unpluggedDisplayMovesTheHUDToTheNearestRemainingOne() {
        let f = HUDPlacement.frame(size: size, screens: [main], saved: CGPoint(x: 2500, y: 400))
        #expect(main.contains(f))
        #expect(f.maxX == main.maxX)
    }

    @Test func growingKeepsTheTopEdge() {
        let start = HUDPlacement.frame(size: CGSize(width: 340, height: 60), screens: [main], saved: nil)
        let grown = HUDPlacement.resized(start, to: CGSize(width: 340, height: 300), screens: [main])
        #expect(grown.maxY == start.maxY && main.contains(grown))
    }

    @Test func coversOnlyASmallPartOfTheScreen() {
        let f = HUDPlacement.frame(size: size, screens: [main], saved: nil)
        #expect(HUDPlacement.coverage(f, of: main) < 0.06)
    }

    @Test func tinyScreenStillFits() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 150)
        #expect(tiny.contains(HUDPlacement.frame(size: size, screens: [tiny], saved: nil)))
    }
}
