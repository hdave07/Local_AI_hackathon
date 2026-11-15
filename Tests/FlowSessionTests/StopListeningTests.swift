import FlowAudio
import FlowCore
@testable import FlowPlanner
import FlowRouting
@testable import FlowSession
import Foundation
import Testing

/// "stop" turns the microphone off (user decision 2026-11-15); "cancel" / "never mind" keep listening.
@Suite("Stop listening", .serialized)
struct StopListeningTests {
    typealias Rig = VoiceSessionCoordinatorTests.Rig

    @Test(arguments: ["stop", "Stop.", "Flow, stop", "stop listening", "okay stop now please", "be quiet", "that's enough",
                      "To me, I'm not sure if I can do it. Stop", "go to sleep"])
    func spokenStopTurnsTheMicrophoneOff(utterance: String) async {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.say(utterance)
        #expect(await eventually { await rig.coordinator.status.listen == .off }, "\(utterance)")
        #expect(await eventually { await !rig.coordinator.isListening }, "\(utterance)")
        #expect(await rig.mock.requests.isEmpty, "a stop never executes anything")
    }

    @Test(arguments: ["cancel", "never mind", "Actually, never mind.", "forget it"])
    func cancelKeepsListening(utterance: String) async {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.say(utterance)
        _ = await rig.turns(1)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await rig.coordinator.isListening, "\(utterance) stopped listening")
        await rig.coordinator.stopListening()
    }

    @Test func nothingHeardAfterStopIsActedOn() async {
        let rig = Rig()
        #expect(await rig.listen())
        rig.mic.say("stop")
        rig.mic.say("Open Notes")
        try? await Task.sleep(for: .milliseconds(400))
        #expect(await rig.mock.requests.isEmpty)
    }

    @Test func stopListeningShowsOffImmediately() async {
        let rig = Rig()
        #expect(await rig.listen())
        await rig.coordinator.stopListening()
        #expect(await rig.coordinator.status.listen == .off)
        #expect(await !rig.coordinator.isListening)
    }

    @Test func typedStopStopsTheTaskEvenWhenNotListening() async throws {
        let rig = Rig()
        let t = try #require(await rig.coordinator.submit("stop"))
        #expect(t.say == ["Nothing to stop."])
    }
}

@Suite("Control phrases are recognized by pattern, not by exact text")
struct ControlPhraseTests {
    @Test(arguments: [
        ("stop", ControlCommand.stop), ("Stop!", .stop), ("hey flow stop", .stop), ("stop listening please", .stop),
        ("okay, that's enough", .stop), ("pause", .stop), ("I'm done talking. Stop.", .stop),
        ("cancel", .cancel), ("cancel that", .cancel), ("never mind", .cancel), ("forget about it", .cancel),
        ("uh, never mind", .cancel), ("stop dictation", .stopDictation), ("please stop dictation now", .stopDictation),
    ])
    func recognized(utterance: String, expected: ControlCommand) {
        #expect(DeterministicRouter.route(utterance)?.control == expected, "\(utterance)")
    }

    @Test(arguments: ["stop the music", "the bus stop is near", "cancel my meeting", "don't stop believing",
                      "I said stop, but I don't want you to stop", "never mind the weather, open Notes", "open Notes"])
    func ordinarySentencesAreNotControls(utterance: String) {
        #expect(DeterministicRouter.route(utterance) == nil, "\(utterance)")
    }
}
