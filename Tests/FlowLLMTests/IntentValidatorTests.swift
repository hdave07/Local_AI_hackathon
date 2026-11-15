import FlowCore
@testable import FlowLLM
import Testing

@Suite("Valid classifications")
struct ValidClassificationTests {
    @Test func activateAppNormalizesTarget() throws {
        // Exact shape observed from Bonsai 2B in LM Studio.
        let json = #"{"kind": "direct", "action": "activate_app", "target": "notes_app", "detail": "", "summary": "Opening notes application"}"#
        let intent = try validate(json).get()
        #expect(intent.kind == .direct)
        #expect(intent.action == .activateApp(.notes))
        #expect(intent.risk == .low)
        #expect(intent.source == .model(id: Fixtures.model))
        #expect(intent.summary == "Opening notes application")
    }

    @Test(arguments: [
        (Fixtures.intentJSON(action: "tile_windows", target: "mail,calendar"),
         FlowAction.tileWindows(left: .mail, right: .calendar)),
        (Fixtures.intentJSON(action: "tile_windows", target: "Calendar and Mail"),
         .tileWindows(left: .calendar, right: .mail)),
        (Fixtures.intentJSON(action: "move_window", target: "active", detail: "left_half"),
         .moveWindow(.active, .leftHalf)),
        (Fixtures.intentJSON(action: "move_window", target: "safari", detail: "right"),
         .moveWindow(.app(.safari), .rightHalf)),
        (Fixtures.intentJSON(action: "resize_window", target: "", detail: "wider"),
         .resizeWindow(.active, .wider)),
        (Fixtures.intentJSON(action: "click_element", target: "Reply"), .clickElement(label: "Reply")),
        (Fixtures.intentJSON(action: "focus", target: "To"), .focus(label: "To")),
        (Fixtures.intentJSON(action: "scroll", detail: "down"), .scroll(.down)),
        (Fixtures.intentJSON(kind: "edit", action: "replace_text", target: "3", detail: "3:30"),
         .replaceText(old: "3", new: "3:30")),
        (Fixtures.intentJSON(kind: "dictation", action: "insert_text", detail: "Hello there"),
         .insertText("Hello there")),
        (Fixtures.intentJSON(kind: "task", action: "create_draft", target: "Sarah", detail: "I can meet"),
         .createDraft(recipient: "Sarah", content: "I can meet")),
        (Fixtures.intentJSON(action: "read_message", target: "Sarah tomorrow"), .readMessage(query: "Sarah tomorrow")),
        (Fixtures.intentJSON(action: "query_calendar", target: "tomorrow 4 pm"),
         .queryCalendar(timeExpression: "tomorrow 4 pm")),
        (Fixtures.intentJSON(action: "request_review"), .requestReview),
        (Fixtures.intentJSON(action: "request_send"), .requestSend),
    ])
    func typedActions(json: String, expected: FlowAction) throws {
        #expect(try validate(json).get().action == expected)
    }

    @Test func sendIsExternalRisk() throws {
        let intent = try validate(Fixtures.intentJSON(action: "request_send")).get()
        #expect(intent.risk == .external)
    }

    @Test(arguments: ["unsupported", "clarification"])
    func nonActionKinds(kind: String) throws {
        let intent = try validate(Fixtures.intentJSON(kind: kind, action: "none", summary: "Which Sarah?")).get()
        #expect(intent.action == nil)
        #expect(intent.kind.rawValue == kind)
        #expect(intent.summary == "Which Sarah?")
    }

    @Test func emptySummaryGetsFallback() throws {
        let intent = try validate(Fixtures.intentJSON(action: "activate_app", target: "mail", summary: "")).get()
        #expect(intent.summary == "activate_app: Mail")
    }
}

@Suite("Invalid classifications are rejected")
struct InvalidClassificationTests {
    @Test(arguments: [
        "Sure! Opening Notes.",
        "```json\n{\"kind\":\"direct\",\"action\":\"activate_app\",\"target\":\"notes\",\"detail\":\"\",\"summary\":\"\"}\n```",
        "[]",
        "{\"kind\":\"direct\",\"action\":\"activate_app\"",
        "",
        "null",
    ])
    func malformedJSON(content: String) {
        guard case .failure(.malformedJSON) = validate(content) else {
            Issue.record("expected malformedJSON for \(content.debugDescription), got \(validate(content))")
            return
        }
    }

    @Test(arguments: [
        // The exact verified LM Studio output shape is NOT the spec contract.
        "open_app", "run_shell", "applescript", "delete_message", "ACTIVATE_APP", "",
    ])
    func unsupportedActions(action: String) {
        #expect(validate(Fixtures.intentJSON(action: action, target: "notes")) == .failure(.unsupportedAction(action)))
    }

    @Test func userVerifiedTwoFieldShapeIsRejected() {
        let result = validate(#"{"action":"open_app","target":"notes"}"#)
        #expect(result == .failure(.schemaViolation("missing field “detail”")))
    }

    @Test func extraFieldRejected() {
        let json = #"{"kind":"direct","action":"activate_app","target":"notes","detail":"","summary":"","command":"rm -rf ~"}"#
        #expect(validate(json) == .failure(.schemaViolation("unexpected field “command”")))
    }

    @Test func nonStringFieldRejected() {
        let json = #"{"kind":"direct","action":"activate_app","target":["notes"],"detail":"","summary":""}"#
        #expect(validate(json) == .failure(.schemaViolation("field “target” must be a string")))
    }

    @Test(arguments: ["control", "confirmation", "execute", ""])
    func disallowedKinds(kind: String) {
        guard case .failure(.schemaViolation) = validate(Fixtures.intentJSON(kind: kind, action: "none")) else {
            Issue.record("kind \(kind) should be rejected")
            return
        }
    }

    @Test(arguments: [
        Fixtures.intentJSON(action: "activate_app", target: "Terminal"),
        Fixtures.intentJSON(action: "activate_app", target: ""),
        Fixtures.intentJSON(action: "tile_windows", target: "mail"),
        Fixtures.intentJSON(action: "tile_windows", target: "mail,mail"),
        Fixtures.intentJSON(action: "tile_windows", target: "mail,calendar,notes"),
        Fixtures.intentJSON(action: "move_window", target: "active", detail: "x=10,y=20"),
        Fixtures.intentJSON(action: "move_window", target: "Xcode", detail: "left_half"),
        Fixtures.intentJSON(action: "resize_window", target: "active", detail: "800x600"),
        Fixtures.intentJSON(action: "scroll", detail: "sideways"),
    ])
    func unsupportedTargets(json: String) {
        guard case .failure(.unsupportedTarget) = validate(json) else {
            Issue.record("expected unsupportedTarget for \(json), got \(validate(json))")
            return
        }
    }

    @Test(arguments: [
        Fixtures.intentJSON(kind: "edit", action: "activate_app", target: "notes"),
        Fixtures.intentJSON(kind: "dictation", action: "replace_text", target: "a", detail: "b"),
        Fixtures.intentJSON(kind: "unsupported", action: "request_send"),
        Fixtures.intentJSON(kind: "clarification", action: "click_element", target: "OK"),
        Fixtures.intentJSON(kind: "direct", action: "none"),
        Fixtures.intentJSON(kind: "edit", action: "replace_text", target: "3", detail: "3"),
    ])
    func inconsistentIntents(json: String) {
        guard case .failure(.inconsistentIntent) = validate(json) else {
            Issue.record("expected inconsistentIntent for \(json), got \(validate(json))")
            return
        }
    }

    @Test(arguments: [
        Fixtures.intentJSON(action: "click_element", target: "   "),
        Fixtures.intentJSON(action: "click_element", target: "Re\u{0007}ply"),
        Fixtures.intentJSON(action: "click_element", target: String(repeating: "x", count: 101)),
        Fixtures.intentJSON(kind: "edit", action: "replace_text", target: "3", detail: ""),
        Fixtures.intentJSON(action: "create_draft", target: "", detail: "hi"),
    ])
    func invalidArguments(json: String) {
        guard case .failure(.schemaViolation) = validate(json) else {
            Issue.record("expected schemaViolation for \(json), got \(validate(json))")
            return
        }
    }
}

@Suite("edit_text is deterministic-only (ADR 0010)")
struct EditTextIsNotModelEmittableTests {
    @Test func modelOutputNamingEditTextIsRejected() {
        let json = Fixtures.intentJSON(kind: "edit", action: "edit_text", target: "", detail: "remove the last sentence")
        guard case .failure(.unsupportedAction("edit_text")) = validate(json) else {
            Issue.record("edit_text from the model must be rejected"); return
        }
    }

    @Test func schemaNeverOffersEditText() {
        #expect(!IntentSchema.allowedActionNames.contains("edit_text"))
        #expect(IntentSchema.allowedActionNames.contains("replace_text"))
    }
}
