@testable import FlowBenchCLI
import FlowCore
import FlowLLM
import Foundation
import Testing

@Suite("T-002 benchmark harness (offline)")
struct BenchmarkHarnessTests {
    static let fixturesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "fixtures/bonsai-benchmark.json")

    @Test func fixtureSetHasRequiredSizes() throws {
        let f = try BenchmarkFixtures.load(Self.fixturesURL)
        #expect(f.intent.count == 30)
        #expect(f.ambiguous.count == 15)
        #expect(f.malformed.count == 10)
        #expect(f.intent.filter { $0.tags?.contains("email-search") == true }.count >= 4)
        #expect(f.intent.filter { $0.tags?.contains("draft-content") == true }.count >= 4)
        #expect(Set((f.intent + f.ambiguous).map(\.id)).count == 45)
        #expect((f.intent + f.ambiguous).allSatisfy { !$0.accept.isEmpty })
    }

    @Test func everyMalformedOutputIsRejectedWithTheExpectedError() throws {
        let f = try BenchmarkFixtures.load(Self.fixturesURL)
        for (c, got, ok) in checkMalformed(f.malformed, modelID: "m") {
            #expect(ok, "\(c.id): expected \(c.expectError), got \(got)")
        }
    }

    func intent(_ action: FlowAction?, kind: IntentKind = .direct) -> Intent {
        Intent(kind: kind, action: action, summary: "s", source: .model(id: "m"))
    }

    @Test func matcherSemantics() {
        let draft = intent(.createDraft(recipient: "Sarah", content: "I can meet tomorrow"), kind: .task)
        #expect(Matcher(action: "create_draft", contains: ["recipient": "sarah", "content": "meet tomorrow"]).matches(draft))
        #expect(!Matcher(action: "create_draft", contains: ["content": "friday"]).matches(draft))
        #expect(!Matcher(action: "create_draft", nonEmpty: ["content"]).matches(
            intent(.createDraft(recipient: "Sarah", content: ""), kind: .task)))
        #expect(Matcher(action: "activate_app", args: ["app": "notes"]).matches(intent(.activateApp(.notes))))
        #expect(!Matcher(action: "read_message").matches(intent(.queryCalendar(timeExpression: "sarah"))))
        #expect(Matcher(kind: "clarification").matches(intent(nil, kind: .clarification)))
        #expect(!Matcher().matches(intent(.requestSend)))  // empty matcher never passes
        #expect(Matcher(action: "move_window", args: ["window": "Mail"]).matches(intent(.moveWindow(.app(.mail), .leftHalf))))
    }

    @Test func percentileInterpolates() {
        #expect(percentile([1, 2, 3, 4], 50) == 2.5)
        #expect(percentile([10], 95) == 10)
        #expect(percentile([], 50).isNaN)
    }
}
