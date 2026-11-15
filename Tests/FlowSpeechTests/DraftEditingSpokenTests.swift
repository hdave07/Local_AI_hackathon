import FlowAudio
import FlowCore
@testable import FlowPlanner
import FlowRouting
@testable import FlowSession
@testable import FlowSpeech
import Foundation
import Testing

/// The T-023B acceptance sequence by voice: scripted recognizer → coordinator → router →
/// planner → MockExecutor (FlowText over simulated drafts) → spoken feedback. No audio,
/// no macOS automation.
@Suite("Acceptance: draft editing by voice (mock executor)", .serialized)
struct DraftEditingSpokenTests {
    func draftBody(_ h: SpeechHarness) async -> String? {
        await h.mock.world.drafts.values.first?.body
    }

    func turn(_ h: SpeechHarness, _ utterance: String, expect predicate: @escaping (String) -> Bool) async -> Bool {
        let before = await h.said.count
        h.transcriber.say(utterance)
        let ok = await eventually { await h.said.dropFirst(before).contains(where: predicate) }
        await h.waitUntilQuiet()
        return ok
    }

    @Test func acceptanceSequence() async throws {
        let h = await SpeechHarness()
        await h.listen()
        #expect(await turn(h, "Find Sarah's email.") { $0.hasPrefix("Which Sarah?") })
        h.transcriber.say("The first one.")
        _ = await eventually { if case .completed = await h.state { return true }; return false }
        await h.waitUntilQuiet()
        h.transcriber.say("Reply saying I can meet at 3:30.")
        #expect(await eventually { await draftBody(h) == "I can meet at 3:30" })
        await h.waitUntilQuiet()

        #expect(await turn(h, "Actually, change 3:30 to 4.") { $0.contains("The draft now says") && $0.contains("I can meet at 4") })
        #expect(await draftBody(h) == "I can meet at 4")

        #expect(await turn(h, "Also say I'll send the details tonight.") { $0.contains("I'll send the details tonight") })
        #expect(await draftBody(h) == "I can meet at 4. I'll send the details tonight.")

        #expect(await turn(h, "What does the draft say?") { $0.hasPrefix("Here's the draft") && $0.contains("I'll send the details tonight") })

        #expect(await turn(h, "Undo that last change.") { $0.hasPrefix("Undone") })
        #expect(await draftBody(h) == "I can meet at 4")

        #expect(await h.mock.world.drafts.count == 1, "one draft throughout")
        #expect(await h.mock.world.sent.isEmpty, "nothing sent")
        await h.coordinator.stopListening()
    }

    @Test func whichOccurrenceIsAskedAloudAndAnsweredByVoice() async throws {
        let h = await SpeechHarness()
        await h.listen()
        #expect(await turn(h, "Find Sarah's email.") { $0.hasPrefix("Which Sarah?") })
        h.transcriber.say("Sarah Chen")
        _ = await eventually { if case .completed = await h.state { return true }; return false }
        await h.waitUntilQuiet()
        h.transcriber.say("Reply saying meet at 3 or call at 3")
        #expect(await eventually { await draftBody(h) == "meet at 3 or call at 3" })
        await h.waitUntilQuiet()

        #expect(await turn(h, "Change 3 to 4") { $0.lowercased().contains("which") })
        #expect(await draftBody(h) == "meet at 3 or call at 3", "nothing changes while asking")
        #expect(await turn(h, "the second one") { $0.contains("The draft now says") })
        #expect(await draftBody(h) == "meet at 3 or call at 4")
        await h.coordinator.stopListening()
    }
}
