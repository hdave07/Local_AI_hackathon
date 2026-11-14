import FlowCore
import Foundation

/// The restricted wire contract sent to Bonsai. Deliberately flat (five string
/// fields) so a 2B model can follow it; strict per-action typing happens in
/// `IntentValidator`, outside the model (spec 02 §16).
public enum IntentSchema {
    public static let name = "flow_intent"
    public static let fields = ["kind", "action", "target", "detail", "summary"]
    public static let noAction = "none"

    public static var allowedActionNames: [String] {
        ActionType.allCases.map(\.rawValue) + [noAction]
    }

    public static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": fields,
            "properties": [
                "kind": ["type": "string", "enum": IntentKind.modelEmittable.map(\.rawValue)],
                "action": ["type": "string", "enum": allowedActionNames],
                "target": ["type": "string", "maxLength": 200],
                "detail": ["type": "string", "maxLength": 2000],
                "summary": ["type": "string", "maxLength": 200],
            ],
        ]
    }

    public static let systemPrompt: String = """
        You convert one macOS voice command into a JSON object. Do not perform it.
        Fields: kind, action, target, detail, summary. All are strings; use "" when unused.

        kind: direct | edit | task | dictation | clarification | unsupported
        action and how to fill target/detail:
        - activate_app: target = app (mail, calendar, notes, finder, safari)
        - tile_windows: target = two apps separated by a comma, left first
        - move_window: target = app or "active"; detail = left_half | right_half | maximize | center
        - resize_window: target = app or "active"; detail = wider | narrower | taller | shorter | larger | smaller
        - click_element: target = visible button or control label
        - focus: target = visible field or control label
        - scroll: detail = up | down | top | bottom
        - insert_text: detail = exact text to type
        - replace_text: target = existing text; detail = replacement text
        - create_draft: target = recipient name; detail = what the message should say
        - read_message: target = what identifies the email (sender, subject, time)
        - query_calendar: target = the time being asked about
        - request_review: review the current draft
        - request_send: send the current draft
        - none: only with kind clarification or unsupported
        Use kind unsupported with action none for anything else. Use kind clarification with \
        action none if the command is too vague; put the question in summary.
        summary = a short description for the user.

        Examples:
        "open notes" -> {"kind":"direct","action":"activate_app","target":"notes","detail":"","summary":"Open Notes"}
        "put mail and calendar side by side" -> {"kind":"direct","action":"tile_windows","target":"mail,calendar","detail":"","summary":"Tile Mail and Calendar"}
        "make this window a bit wider" -> {"kind":"direct","action":"resize_window","target":"active","detail":"wider","summary":"Widen the active window"}
        "change 3 to 3:30" -> {"kind":"edit","action":"replace_text","target":"3","detail":"3:30","summary":"Replace 3 with 3:30"}
        "reply to sarah that I can meet" -> {"kind":"task","action":"create_draft","target":"sarah","detail":"I can meet","summary":"Draft a reply to Sarah"}
        "do I have anything at four tomorrow" -> {"kind":"direct","action":"query_calendar","target":"tomorrow 4 pm","detail":"","summary":"Check tomorrow at 4 pm"}
        "order me a pizza" -> {"kind":"unsupported","action":"none","target":"","detail":"","summary":"Ordering food is not supported"}
        """
}
