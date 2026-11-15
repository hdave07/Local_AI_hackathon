@testable import FlowSpeech
import Foundation
import Testing

/// Real macOS speech. Opt in: FLOW_LIVE_TTS=1 (availability, silent) and
/// FLOW_LIVE_TTS_AUDIBLE=1 (actually speaks a short phrase through the speakers).
@Suite("Live system speech", .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_TTS"] == "1"), .serialized)
struct LiveSpeechTests {
    @Test func aVoiceIsAvailable() async throws {
        let out = SystemSpeechOutput()
        let availability = await out.availability()
        print("LIVE TTS availability:", availability)
        guard case .available = availability else { Issue.record("no voice: \(availability)"); return }
    }

    @Test func missingRequestedVoiceFallsBack() async throws {
        let out = SystemSpeechOutput(voiceIdentifier: "com.example.no-such-voice")
        guard case .available = await out.availability() else { Issue.record("no fallback voice"); return }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_TTS_AUDIBLE"] == "1"))
    func speaksAndCanBeInterrupted() async throws {
        let out = SystemSpeechOutput()
        let start = ContinuousClock.now
        #expect(await out.speak("Which Sarah?") == .finished)
        print("LIVE TTS 'Which Sarah?' took", ContinuousClock.now - start)
        let long = Task { await out.speak("This is a long sentence that Flow will be asked to stop before it finishes speaking it.") }
        try await Task.sleep(for: .milliseconds(600))
        await out.stop()
        #expect(await long.value == .interrupted)
    }
}
