import FlowAudio
import FlowCore
import FlowLLM
import Foundation
import Testing

@Suite("Microphone permission gate")
struct MicrophoneGateTests {
    @Test func authorizedPassesWithoutPrompt() async throws {
        let p = FakePermission(.authorized)
        try await MicrophoneGate.ensureAccess(p)
        #expect(p.requestCount == 0)
    }

    @Test func undeterminedPromptsOnceAndPassesWhenGranted() async throws {
        let p = FakePermission(.notDetermined, grantOnRequest: true)
        try await MicrophoneGate.ensureAccess(p)
        #expect(p.requestCount == 1)
    }

    @Test func undeterminedThenRefusedIsDenied() async {
        let p = FakePermission(.notDetermined, grantOnRequest: false)
        await #expect(throws: AudioError.microphoneDenied) { try await MicrophoneGate.ensureAccess(p) }
    }

    @Test func deniedIsReportedWithoutRePrompting() async {
        let p = FakePermission(.denied)
        await #expect(throws: AudioError.microphoneDenied) { try await MicrophoneGate.ensureAccess(p) }
        #expect(p.requestCount == 0)
    }

    @Test func restrictedIsDistinct() async {
        await #expect(throws: AudioError.microphoneRestricted) {
            try await MicrophoneGate.ensureAccess(FakePermission(.restricted))
        }
    }

    @Test func missingInputDevice() async {
        await #expect(throws: AudioError.noInputDevice) {
            try await MicrophoneGate.ensureAccess(FakePermission(.authorized, hasDevice: false))
        }
    }

    @Test func micErrorsDoNotPromiseVoiceRecovery() {
        #expect(!AudioError.microphoneDenied.isRecoverableByVoice)
        #expect(!AudioError.noInputDevice.isRecoverableByVoice)
        #expect(AudioError.microphoneDenied.userMessage.contains("System Settings"))
    }
}

@Suite("Voice pipeline")
struct VoicePipelineTests {
    @Test func openNotesReachesMockConsumerAsTypedAction() async throws {
        let transcriber = FakeTranscriber([
            .event(.voiceActivity(.speechStarted)),
            .event(.hypothesis("open")),
            .event(.hypothesis("open notes")),
            .event(.confirmed("Open Notes.", language: "en")),
            .event(.voiceActivity(.speechEnded)),
            .pause(.milliseconds(200)),
        ])
        let classifier = FakeClassifier(["open notes": openNotesIntent()])
        let sink = MockActionConsumer()
        let pipeline = makePipeline(transcriber, classifier: classifier, sink: sink)
        let (log, recorder) = record(pipeline)

        try await pipeline.run()
        await settle()
        recorder.cancel()

        #expect(classifier.calls == ["Open Notes."])
        #expect(await sink.actions == [.activateApp(.notes)])
        let routed = try #require(await sink.received.first)
        #expect(routed.routedBy == .model)
        #expect(routed.utterance.language == "en")
        #expect(routed.utterance.sessionID == pipeline.sessionID)

        let states = await log.states
        #expect(states.first == .checkingPermission)
        #expect(states.contains(.preparing))
        #expect(states.contains(.listening))
        #expect(states.contains(.hearing(.init(confirmed: "", hypothesis: "open notes"))))
        #expect(states.contains(.routing("Open Notes.")))
        #expect(states.last == .stopped)
    }

    @Test func hypothesisOnlySpeechIsNeverRouted() async throws {
        let transcriber = FakeTranscriber([.event(.hypothesis("send it"))])
        let classifier = FakeClassifier()
        let sink = MockActionConsumer()
        let pipeline = makePipeline(transcriber, classifier: classifier, sink: sink)
        let (log, recorder) = record(pipeline)

        try await pipeline.run()
        await settle()
        recorder.cancel()

        #expect(classifier.calls.isEmpty)
        #expect(await sink.received.isEmpty)
        #expect(await log.events.contains(.incomplete(.init(confirmed: "", hypothesis: "send it"))))
    }

    @Test(arguments: ["Stop.", "Cancel", "Flow, stop.", "flow stop dictation"])
    func controlPhrasesBypassTheModel(phrase: String) async throws {
        let transcriber = FakeTranscriber([.event(.confirmed(phrase, language: nil))])
        let classifier = FakeClassifier()
        let sink = MockActionConsumer()
        try await makePipeline(transcriber, classifier: classifier, sink: sink).run()

        #expect(classifier.calls.isEmpty)
        let routed = try #require(await sink.received.first)
        #expect(routed.routedBy == .deterministic)
        #expect(routed.intent?.kind == .control)
    }

    @Test(arguments: ["stop the music", "cancel my meeting", "please stop dictation now"])
    func embeddedControlWordsGoToTheModel(phrase: String) async throws {
        let transcriber = FakeTranscriber([.event(.confirmed(phrase, language: nil))])
        let classifier = FakeClassifier()
        let sink = MockActionConsumer()
        try await makePipeline(transcriber, classifier: classifier, sink: sink).run()

        #expect(classifier.calls == [phrase])
        #expect(await sink.received.first?.routedBy == .model)
    }

    @Test func stopCancelsInFlightClassification() async throws {
        let transcriber = FakeTranscriber([
            .event(.confirmed("open notes", language: nil)),
            .pause(.milliseconds(150)),  // first utterance finalizes; slow model call starts
            .event(.confirmed("stop", language: nil)),
            .pause(.milliseconds(150)),
        ])
        let classifier = FakeClassifier(delay: .seconds(5), ["open notes": openNotesIntent()])
        let sink = MockActionConsumer()
        let started = ContinuousClock.now
        try await makePipeline(transcriber, classifier: classifier, sink: sink).run()

        #expect(ContinuousClock.now - started < .seconds(2))
        let received = await sink.received
        #expect(received.count == 2)
        #expect(received.first?.intent?.control == .stop)  // control delivered first
        #expect(received.last?.outcome == .failure(.cancelled))
        #expect(await sink.actions.isEmpty)
    }

    @Test func stopWinsOverAModelAnswerThatIgnoresCancellation() async throws {
        let transcriber = FakeTranscriber([
            .event(.confirmed("open notes", language: nil)),
            .pause(.milliseconds(100)),
            .event(.confirmed("stop", language: nil)),
            .pause(.milliseconds(400)),
        ])
        let classifier = FakeClassifier(delay: .milliseconds(250), ignoresCancellation: true, ["open notes": openNotesIntent()])
        let sink = MockActionConsumer()
        try await makePipeline(transcriber, classifier: classifier, sink: sink).run()
        let received = await sink.received
        #expect(received.first?.intent?.control == .stop)
        #expect(received.last?.outcome == .failure(.cancelled))
        #expect(await sink.actions.isEmpty)
    }

    @Test func commandsAreClassifiedInSpokenOrder() async throws {
        let scroll = Intent(kind: .direct, action: .scroll(.down), summary: "s", source: .model(id: "fake"))
        let transcriber = FakeTranscriber([
            .event(.confirmed("open notes", language: nil)), .pause(.milliseconds(100)),
            .event(.confirmed("scroll down", language: nil)), .pause(.milliseconds(100)),
        ])
        let classifier = FakeClassifier(delay: .milliseconds(150), ["open notes": openNotesIntent(), "scroll down": scroll])
        let sink = MockActionConsumer()
        try await makePipeline(transcriber, classifier: classifier, sink: sink).run()
        #expect(await sink.actions == [.activateApp(.notes), .scroll(.down)])
    }

    @Test func classifierFailureIsDeliveredNotSwallowed() async throws {
        let transcriber = FakeTranscriber([.event(.confirmed("order me a pizza", language: nil))])
        let sink = MockActionConsumer()
        try await makePipeline(transcriber, classifier: FakeClassifier(), sink: sink).run()
        #expect(await sink.received.first?.outcome == .failure(.unsupportedAction("unknown")))
    }

    @Test func deniedMicrophoneNeverStartsCapture() async {
        let transcriber = FakeTranscriber([.event(.confirmed("open notes", language: nil))])
        let pipeline = makePipeline(transcriber, permission: FakePermission(.denied), classifier: FakeClassifier())
        #expect(await runCapturing(pipeline) == .microphoneDenied)
        #expect(transcriber.prepareCount == 0)
        #expect(transcriber.startCount == 0)
        #expect(await pipeline.state == .failed(.microphoneDenied))
    }

    @Test func missingLicenseFailsDuringPrepare() async {
        let transcriber = FakeTranscriber([], prepareError: .licenseMissing)
        let pipeline = makePipeline(transcriber, classifier: FakeClassifier())
        #expect(await runCapturing(pipeline) == .licenseMissing)
        #expect(transcriber.startCount == 0)
        #expect(await pipeline.state == .failed(.licenseMissing))
    }

    @Test func unavailableFeatureIsTyped() async {
        let transcriber = FakeTranscriber([], prepareError: .featureUnavailable("custom vocabulary with Whisper"))
        let pipeline = makePipeline(transcriber, classifier: FakeClassifier())
        #expect(await runCapturing(pipeline) == .featureUnavailable("custom vocabulary with Whisper"))
    }

    @Test func engineFailureMidStreamStillRoutesStableText() async {
        let transcriber = FakeTranscriber([
            .event(.confirmed("open notes", language: nil)),
            .fail(.engineFailed("device disconnected")),
        ])
        let sink = MockActionConsumer()
        let pipeline = makePipeline(transcriber, classifier: FakeClassifier(["open notes": openNotesIntent()]), sink: sink)
        #expect(await runCapturing(pipeline) == .engineFailed("device disconnected"))
        #expect(await pipeline.state == .failed(.engineFailed("device disconnected")))
        #expect(await sink.actions == [.activateApp(.notes)])
    }

    @Test func runningTwiceIsRejected() async throws {
        let transcriber = FakeTranscriber([], holdOpen: true)
        let pipeline = makePipeline(transcriber, permission: nil, classifier: FakeClassifier())
        let first = Task { await runCapturing(pipeline) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await runCapturing(pipeline) == .alreadyRunning)
        await pipeline.stop()
        #expect(await first.value == nil)
        #expect(await pipeline.state == .stopped)
    }

    @Test func stopEndsListeningAndFlushesStableText() async throws {
        let transcriber = FakeTranscriber([.event(.confirmed("open notes", language: nil))], holdOpen: true)
        let sink = MockActionConsumer()
        // Long trailing silence: only stop() can finalize.
        let pipeline = makePipeline(
            transcriber, permission: nil, classifier: FakeClassifier(["open notes": openNotesIntent()]), sink: sink,
            policy: EndpointPolicy(trailingSilence: 60, unconfirmedTailTimeout: 60, maxUtteranceDuration: 60))
        let run = Task { await runCapturing(pipeline) }
        try await Task.sleep(for: .milliseconds(50))
        await pipeline.stop()
        #expect(await run.value == nil)
        #expect(await sink.actions == [.activateApp(.notes)])
    }
}

// MARK: - Integration with the real Bonsai classifier (HTTP mocked)

/// Answers every chat completion with a fixed intent JSON for the default Bonsai model.
private struct CannedLMStudio: HTTPTransport {
    let content: String

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let envelope: [String: Any] = [
            "model": LMStudioConfiguration.defaultModelID,
            "choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Voice pipeline + BonsaiIntentClassifier")
struct VoiceToBonsaiIntegrationTests {
    func classifier(_ json: String) throws -> BonsaiIntentClassifier {
        BonsaiIntentClassifier(
            client: LMStudioClient(configuration: try LMStudioConfiguration(), transport: CannedLMStudio(content: json)))
    }

    @Test func spokenOpenNotesBecomesValidatedActivateApp() async throws {
        let json = #"{"kind":"direct","action":"activate_app","target":"notes","detail":"","summary":"Open Notes"}"#
        let transcriber = FakeTranscriber([.event(.hypothesis("open notes")), .event(.confirmed("Open Notes.", language: "en"))])
        let sink = MockActionConsumer()
        let pipeline = VoicePipeline(
            transcriber: transcriber, permission: FakePermission(.authorized), classifier: try classifier(json),
            sink: sink, policy: fastPolicy, tickInterval: .milliseconds(5))
        try await pipeline.run()

        let routed = try #require(await sink.received.first)
        #expect(routed.intent?.action == .activateApp(.notes))
        #expect(routed.intent?.risk == .low)
        #expect(routed.intent?.source == .model(id: LMStudioConfiguration.defaultModelID))
    }

    @Test func modelProposingDisallowedTargetIsRejectedBeforeConsumer() async throws {
        let json = #"{"kind":"direct","action":"activate_app","target":"terminal","detail":"","summary":"x"}"#
        let transcriber = FakeTranscriber([.event(.confirmed("open terminal", language: nil))])
        let sink = MockActionConsumer()
        try await VoicePipeline(
            transcriber: transcriber, permission: nil, classifier: try classifier(json), sink: sink,
            policy: fastPolicy, tickInterval: .milliseconds(5)
        ).run()
        #expect(await sink.received.first?.outcome == .failure(.unsupportedTarget(action: "activate_app", target: "terminal")))
        #expect(await sink.actions.isEmpty)
    }
}
