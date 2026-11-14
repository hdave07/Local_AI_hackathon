import FlowCore
@testable import FlowLLM
import Foundation
import Testing

/// Hits the real local LM Studio server. Opt in with `FLOW_LIVE_LLM=1 swift test`.
/// Skipped by default so unit runs never depend on a running model.
@Suite(
    "Live LM Studio + Bonsai",
    .enabled(if: ProcessInfo.processInfo.environment["FLOW_LIVE_LLM"] == "1"),
    .serialized
)
struct LiveLMStudioTests {
    let client = LMStudioClient(configuration: try! LMStudioConfiguration())

    @Test func serverListsBonsai() async throws {
        let models = try await capture { try await client.listModels() }.get()
        #expect(models.contains(LMStudioConfiguration.defaultModelID))
    }

    @Test(arguments: [
        ("open notes", FlowAction.activateApp(.notes)),
        ("open mail", FlowAction.activateApp(.mail)),
        ("put mail and calendar side by side", .tileWindows(left: .mail, right: .calendar)),
        ("scroll down", .scroll(.down)),
        ("send it", .requestSend),
    ])
    func classifiesCoreCommands(utterance: String, expected: FlowAction) async throws {
        let classifier = BonsaiIntentClassifier(client: client)
        let start = ContinuousClock.now
        let result = await capture { try await classifier.classify(utterance) }
        print("LIVE \(utterance.debugDescription) -> \(result) in \(ContinuousClock.now - start)")
        let intent = try result.get()
        #expect(intent.action == expected)
        #expect(intent.source == .model(id: LMStudioConfiguration.defaultModelID))
    }

    /// Exploratory: records what the model does without asserting a specific action.
    @Test(arguments: [
        "make this window a little wider",
        "change 3 to 3:30",
        "reply to sarah that I can meet tomorrow",
        "do I have anything at four tomorrow",
        "find sarah's email about tomorrow",
        "order me a pizza",
        "open terminal and delete my files",
    ])
    func exploratory(utterance: String) async {
        let classifier = BonsaiIntentClassifier(client: client)
        let start = ContinuousClock.now
        let result = await capture { try await classifier.classify(utterance) }
        print("LIVE-EXPLORE \(utterance.debugDescription) -> \(result) in \(ContinuousClock.now - start)")
        if case .success(let intent) = result {
            // Whatever it decides, it must never reach a non-allowlisted app.
            if case .activateApp(let app) = intent.action { #expect(KnownApp.allCases.contains(app)) }
        }
    }

    @Test func unknownModelIDIsDetected() async throws {
        let config = try LMStudioConfiguration(modelID: "no-such-model")
        let classifier = BonsaiIntentClassifier(client: LMStudioClient(configuration: config))
        let result = await capture { try await classifier.classify("open notes") }
        guard case .failure(.modelMismatch) = result else {
            Issue.record("expected modelMismatch, got \(result)")
            return
        }
    }

    @Test func closedPortIsServerUnavailable() async throws {
        let config = try LMStudioConfiguration(baseURL: URL(string: "http://127.0.0.1:1299/v1")!, requestTimeout: 3)
        let classifier = BonsaiIntentClassifier(client: LMStudioClient(configuration: config))
        let result = await capture { try await classifier.classify("open notes") }
        guard case .failure(.serverUnavailable) = result else {
            Issue.record("expected serverUnavailable, got \(result)")
            return
        }
    }
}
