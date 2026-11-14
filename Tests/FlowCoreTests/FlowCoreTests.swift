import FlowCore
import Testing

@Suite("KnownApp normalization")
struct KnownAppTests {
    @Test(arguments: [
        ("notes", KnownApp.notes), ("notes_app", .notes), ("Notes.app", .notes),
        ("the mail app", .mail), ("Apple Calendar", .calendar), ("SAFARI", .safari),
        ("finder", .finder),
    ])
    func parsesAllowlistedNames(raw: String, expected: KnownApp) {
        #expect(KnownApp.parse(raw) == expected)
    }

    @Test(arguments: ["Terminal", "", "notes; rm -rf ~", "/Applications/Notes.app", "System Settings"])
    func rejectsEverythingElse(raw: String) {
        #expect(KnownApp.parse(raw) == nil)
    }
}

@Suite("Risk is derived in code")
struct RiskTests {
    @Test func riskTiers() {
        #expect(FlowAction.activateApp(.notes).risk == .low)
        #expect(FlowAction.tileWindows(left: .mail, right: .calendar).risk == .low)
        #expect(FlowAction.insertText("hi").risk == .content)
        #expect(FlowAction.createDraft(recipient: "Sarah", content: "").risk == .content)
        #expect(FlowAction.requestSend.risk == .external)
    }

    @Test func intentWithoutActionHasNoRisk() {
        let intent = Intent(kind: .unsupported, summary: "x", source: .deterministic)
        #expect(intent.risk == RiskLevel.none)
    }
}

@Suite("Deterministic control router")
struct DeterministicRouterTests {
    @Test(arguments: [
        ("stop", ControlCommand.stop), ("Flow, stop.", .stop), ("cancel", .cancel),
        ("Flow, stop dictation", .stopDictation), ("  STOP  ", .stop),
    ])
    func recognizesStandalonePhrases(input: String, expected: ControlCommand) {
        let intent = DeterministicRouter.route(input)
        #expect(intent?.kind == .control)
        #expect(intent?.control == expected)
        #expect(intent?.source == .deterministic)
        #expect(intent?.action == nil)
    }

    @Test(arguments: ["stop the music", "please cancel my meeting", "open notes", "flow"])
    func ignoresEmbeddedPhrases(input: String) {
        #expect(DeterministicRouter.route(input) == nil)
    }
}
