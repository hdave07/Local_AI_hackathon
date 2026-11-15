import FlowAudio
import FlowCore
import FlowPlanner
import FlowRouting
@testable import FlowSession
import Foundation
import Testing

/// Coordinator tests against FlowPlanner's MockExecutor: nothing touches macOS.
@Suite("VoiceSessionCoordinator (mock executor)")
struct VoiceSessionCoordinatorTests {
    struct Rig {
        let mock: MockExecutor
        let store: IntentRouter
        let coordinator: VoiceSessionCoordinator
        let mic: ScriptedTranscriber

        init(micGranted: Bool = true, failPrepare: AudioError? = nil) {
            mock = MockExecutor(world: sampleWorld())
            store = IntentRouter(model: SilentModel())
            mic = ScriptedTranscriber(failPrepare: failPrepare)
            coordinator = VoiceSessionCoordinator(session: TaskSession(store: store, executor: mock), transcriber: mic,
                                                  permission: FakeMicrophone(granted: micGranted))
        }

        func listen() async -> Bool {
            await coordinator.startListening()
            return await eventually { mic.isStarted }
        }

        func turns(_ n: Int) async -> [SessionTurn] {
            _ = await eventually { await coordinator.turns.count >= n }
            return await coordinator.turns
        }
    }

    // MARK: Voice path

    @Test func spokenOpenNotesIsPlannedAndExecuted() async throws {
        let rig = Rig()
        #expect(await rig.listen())
        #expect(await eventually { await rig.coordinator.status.listen == .listening })
        rig.mic.say("Open Notes")
        let turns = await rig.turns(1)
        let turn = try #require(turns.first)
        #expect(turn.utterance == "Open Notes")
        #expect(turn.source == .voice)
        guard case .completed = turn.state else { Issue.record("state \(turn.state) say \(turn.say)"); return }
        #expect(await rig.mock.world.activeApp == .notes)
        #expect(await rig.mock.requests.map(\.action) == [.activateApp(.notes)])
        #expect(await rig.store.context.activeApp == .notes, "verified state lands in the router's single store")
        await rig.coordinator.stopListening()
        #expect(await rig.coordinator.status.listen == .off)
    }

    @Test func hypothesesAreNeverExecuted() async {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.mumble("open notes")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await rig.coordinator.turns.isEmpty)
        #expect(await rig.mock.requests.isEmpty)
        await rig.coordinator.stopListening()
    }

    @Test func clarificationIsAnsweredByVoice() async throws {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.say("Find Sarah's email")
        let first = await rig.turns(1)
        guard case .awaitingChoice(let q) = try #require(first.last).state else { Issue.record("no question"); return }
        #expect(q.options.count == 2)
        guard case .awaitingChoice(_, let options) = await rig.coordinator.status.task else { Issue.record("HUD not asking"); return }
        #expect(options.count == 2)

        rig.mic.say("the second one")
        let second = await rig.turns(2)
        guard case .completed = try #require(second.last).state else { Issue.record("state \(second.last!.state)"); return }
        let read = await rig.mock.requests.last
        #expect(read?.bindings.message?.id == "m2", "exactly the chosen message")
        #expect(await rig.store.context.selectedMessage?.sender == "Sarah Okafor")
        await rig.coordinator.stopListening()
    }

    @Test func commandsRunInSpokenOrder() async {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.say("Open Notes")
        rig.mic.say("Open Safari")
        _ = await rig.turns(2)
        #expect(await rig.mock.requests.map(\.action) == [.activateApp(.notes), .activateApp(.safari)])
        #expect(await rig.coordinator.turns.map(\.utterance) == ["Open Notes", "Open Safari"])
        await rig.coordinator.stopListening()
    }

    // MARK: Stop / cancel

    @Test func stopInterruptsTheInFlightStep() async throws {
        let rig = Rig()
        await rig.mock.delay(.findMessage, by: .seconds(5))
        #expect(await rig.listen())
        rig.mic.say("Find the email from Priya")
        _ = await eventually { await rig.mock.requests.contains { if case .readMessage = $0.action { true } else { false } } }
        let started = ContinuousClock.now
        rig.mic.say("stop")
        let turns = await rig.turns(2)
        #expect(ContinuousClock.now - started < .seconds(2), "stop did not wait for the slow step")
        let stop = try #require(turns.first { $0.utterance == "stop" })
        #expect(stop.say == ["Stopped."])
        _ = await eventually { await rig.coordinator.turns.count == 2 }
        let find = try #require(await rig.coordinator.turns.first { $0.utterance.hasPrefix("Find") })
        guard case .cancelled = find.state else { Issue.record("find ended \(find.state)"); return }
        #expect(await rig.store.context.selectedMessage == nil, "nothing was opened")
        await rig.coordinator.stopListening()
    }

    @Test func stopDropsQueuedCommands() async {
        let rig = Rig()
        await rig.mock.delay(.activate, by: .milliseconds(500))
        async let first = rig.coordinator.submit("Open Notes")
        try? await Task.sleep(for: .milliseconds(50))
        async let second = rig.coordinator.submit("Open Safari")
        try? await Task.sleep(for: .milliseconds(50))
        _ = await rig.coordinator.submit("cancel")
        _ = await (first, second)
        #expect(await second == nil, "queued command dropped")
        #expect(await !rig.mock.requests.contains { $0.action == .activateApp(.safari) })
    }

    @Test func stopWithNothingRunning() async {
        let rig = Rig()
        #expect(await rig.coordinator.submit("stop")?.say == ["Nothing to stop."])
    }

    // MARK: Typed path

    @Test func typedCommandsUseTheSamePath() async throws {
        let rig = Rig()
        let turn = try #require(await rig.coordinator.submit("Open Notes"))
        #expect(turn.source == .typed)
        guard case .completed = turn.state else { Issue.record("state \(turn.state)"); return }
        #expect(await rig.mock.world.activeApp == .notes)
        #expect(await rig.coordinator.submit("   ") == nil)
    }

    @Test func declinedRequestsExecuteNothing() async {
        let rig = Rig()
        _ = await rig.coordinator.submit("delete the email from Priya")
        #expect(await rig.mock.requests.isEmpty)
    }

    // MARK: Questions and approvals

    @Test func ambiguousCommandShowsTheRoutersQuestion() async throws {
        let rig = Rig()
        let turn = try #require(await rig.coordinator.submit("open it"))
        guard case .awaitingAnswer(let question) = await rig.coordinator.status.task else {
            Issue.record("phase \(await rig.coordinator.status.task) say \(turn.say)")
            return
        }
        #expect(!question.isEmpty)
        #expect(await rig.mock.requests.isEmpty, "nothing executed while asking")
        let answer = try #require(await rig.coordinator.submit("Notes"))
        guard case .completed = answer.state else { Issue.record("answer state \(answer.state) say \(answer.say)"); return }
        #expect(await rig.mock.world.activeApp == .notes)
    }

    @Test func approvalQuestionIsSurfacedAndNoMeansNothingIsSent() async throws {
        let rig = Rig()
        _ = await rig.coordinator.submit("Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.")
        _ = await rig.coordinator.submit("the first one")
        _ = await rig.coordinator.submit("send it")
        guard case .awaitingConfirmation(let prompt) = await rig.coordinator.status.task else {
            Issue.record("phase \(await rig.coordinator.status.task)")
            return
        }
        #expect(prompt.contains("Say “yes, send it” to send"))
        let no = try #require(await rig.coordinator.submit("no"))
        guard case .stopped = no.state else { Issue.record("state \(no.state)"); return }
        #expect(await rig.mock.world.sent.isEmpty)
        #expect(await rig.mock.sendRequests.isEmpty)
    }

    @Test func stopDuringApprovalSendsNothing() async {
        let rig = Rig()
        _ = await rig.coordinator.submit("Find Sarah's email about tomorrow, draft a reply saying I can meet at 3, and show it to me.")
        _ = await rig.coordinator.submit("the first one")
        _ = await rig.coordinator.submit("send it")
        _ = await rig.coordinator.submit("stop")
        _ = await rig.coordinator.submit("yes")
        #expect(await rig.mock.world.sent.isEmpty, "a stale yes after stop never sends")
    }

    // MARK: Audio failures

    @Test func microphoneDeniedReportsAndRunsNothing() async {
        let rig = Rig(micGranted: false)
        await rig.coordinator.startListening()
        #expect(await eventually { if case .failed = await rig.coordinator.status.listen { true } else { false } })
        #expect(await rig.coordinator.turns.isEmpty)
    }

    @Test func missingSpeechLicenseIsReported() async {
        let rig = Rig(failPrepare: .licenseMissing)
        await rig.coordinator.startListening()
        let failed = await eventually { await rig.coordinator.status.listen == .failed(AudioError.licenseMissing.userMessage) }
        #expect(failed)
    }

    @Test func unavailableSpeechModelIsReported() async {
        let rig = Rig(failPrepare: .modelUnavailable("parakeet-v2_476MB"))
        await rig.coordinator.startListening()
        #expect(await eventually {
            await rig.coordinator.status.listen == .failed(AudioError.modelUnavailable("parakeet-v2_476MB").userMessage)
        })
        #expect(await !rig.coordinator.isListening)
        // Typed commands still work without speech.
        #expect(await rig.coordinator.submit("Open Notes")?.state != nil)
    }

    @Test func noRecognizerConfigured() async {
        let coordinator = VoiceSessionCoordinator(
            session: TaskSession(store: IntentRouter(model: SilentModel()), executor: MockExecutor(world: sampleWorld())),
            transcriber: nil, permission: nil)
        await coordinator.startListening()
        #expect(await coordinator.status.listen == .failed("No speech recognizer is configured."))
    }

    @Test func passThroughClassifierNeverRoutes() async throws {
        let intent = try await PassThroughClassifier().classify("delete everything")
        #expect(intent.action == nil)
    }
}
