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
        ActionType.modelEmittable.map(\.rawValue) + [noAction]
    }

    /// The schema, with `properties` in exactly `fields` order. Order matters: the
    /// constrained decoder generates fields in this order (see `OrderedJSON`).
    public static var jsonSchema: OrderedJSON {
        func string(maxLength: Int) -> OrderedJSON {
            .object([("type", .string("string")), ("maxLength", .int(maxLength))])
        }
        func oneOf(_ values: [String]) -> OrderedJSON {
            .object([("type", .string("string")), ("enum", .array(values.map(OrderedJSON.string)))])
        }
        let definitions: [String: OrderedJSON] = [
            "kind": oneOf(IntentKind.modelEmittable.map(\.rawValue)),
            "action": oneOf(allowedActionNames),
            "target": string(maxLength: 200),
            "detail": string(maxLength: 2000),
            "summary": string(maxLength: 200),
        ]
        return .object([
            ("type", .string("object")),
            ("additionalProperties", .bool(false)),
            ("required", .array(fields.map(OrderedJSON.string))),
            ("properties", .object(fields.map { ($0, definitions[$0]!) })),
        ])
    }

    /// T-011 prompt, kept for A/B benchmarking.
    public static let systemPromptV1: String = """
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

    /// V3: V1 plus three compact rules (bare references → clarification, copy values
    /// exactly, email vs calendar) and example values that do not recur elsewhere.
    public static let systemPromptV3: String = """
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
        action none if the command is too vague or only says it/that/her/him; put the question in summary.
        Copy names, times and message words exactly as spoken; never add values. Finding or reading an email is \
        read_message even if it names a day; calendar, free, busy and meetings are query_calendar.
        summary = a short description for the user.

        Examples:
        "open notes" -> {"kind":"direct","action":"activate_app","target":"notes","detail":"","summary":"Open Notes"}
        "put mail and calendar side by side" -> {"kind":"direct","action":"tile_windows","target":"mail,calendar","detail":"","summary":"Tile Mail and Calendar"}
        "make this window a bit wider" -> {"kind":"direct","action":"resize_window","target":"active","detail":"wider","summary":"Widen the active window"}
        "change 3 to 3:30" -> {"kind":"edit","action":"replace_text","target":"3","detail":"3:30","summary":"Replace 3 with 3:30"}
        "reply to omar that the plan looks good" -> {"kind":"task","action":"create_draft","target":"omar","detail":"the plan looks good","summary":"Draft a reply to Omar"}
        "am I busy wednesday at 9" -> {"kind":"direct","action":"query_calendar","target":"wednesday at 9","detail":"","summary":"Check Wednesday at 9"}
        "order me a pizza" -> {"kind":"unsupported","action":"none","target":"","detail":"","summary":"Ordering food is not supported"}
        """


    /// Prompt in use. Benchmarked against V1 in docs/evidence/T-030-voice-improvements.md.
    public static var systemPrompt: String { systemPromptV2 }

    /// V2: explicit mail/calendar/draft routing, copy-exactly rule, clarification for bare
    /// references, and examples whose values do not recur elsewhere (V1's "tomorrow 4 pm"
    /// was copied into unrelated answers).
    public static let systemPromptV2: String = """
        You convert one macOS voice command into a JSON object. Do not perform it.
        Fields: kind, action, target, detail, summary. All are strings; use "" when unused.

        kind: direct | edit | task | dictation | clarification | unsupported
        action and how to fill target/detail:
        - activate_app: target = the app's name as spoken (any app, e.g. notes, calculator, spotify, system settings)
        - tile_windows: target = two apps separated by a comma, left first
        - move_window: target = app or "active"; detail = left_half | right_half | maximize | center
        - resize_window: target = app or "active"; detail = wider | narrower | taller | shorter | larger | smaller
        - click_element: target = visible button or control label
        - focus: target = visible field or control label
        - scroll: detail = up | down | top | bottom
        - insert_text: detail = exact text to type
        - replace_text: target = existing text; detail = replacement text
        - create_draft: target = recipient name; detail = the words the message should say
        - read_message: target = words that identify the email (sender, subject, time)
        - query_calendar: target = the day or time being asked about
        - request_review: review the current draft
        - request_send: send the current draft
        - none: only with kind clarification or unsupported

        Rules:
        - Copy names, dates, times and message words exactly as spoken. Never add a value the user did not say.
        - Finding, opening or reading an email or message is read_message, even if it mentions a day or time.
        - Writing, replying, emailing or telling a person something is create_draft.
        - Questions about being free, busy, meetings, the calendar or the schedule are query_calendar.
        - If the command only says it, that, this, them, her or him without naming the thing, use kind clarification with action none and ask a short question in summary.
        - Closing, deleting or rewriting tone are not supported: kind unsupported, action none.

        Examples:
        "open notes" -> {"kind":"direct","action":"activate_app","target":"notes","detail":"","summary":"Open Notes"}
        "put mail and calendar side by side" -> {"kind":"direct","action":"tile_windows","target":"mail,calendar","detail":"","summary":"Tile Mail and Calendar"}
        "make this window a bit wider" -> {"kind":"direct","action":"resize_window","target":"active","detail":"wider","summary":"Widen the active window"}
        "change 3 to 3:30" -> {"kind":"edit","action":"replace_text","target":"3","detail":"3:30","summary":"Replace 3 with 3:30"}
        "reply to omar that the plan looks good" -> {"kind":"task","action":"create_draft","target":"omar","detail":"the plan looks good","summary":"Draft a reply to Omar"}
        "show nina's message about the trip" -> {"kind":"direct","action":"read_message","target":"nina trip","detail":"","summary":"Find Nina's message about the trip"}
        "am I busy wednesday at 9" -> {"kind":"direct","action":"query_calendar","target":"wednesday at 9","detail":"","summary":"Check Wednesday at 9"}
        "open it" -> {"kind":"clarification","action":"none","target":"","detail":"","summary":"Which app should I open?"}
        "order me a pizza" -> {"kind":"unsupported","action":"none","target":"","detail":"","summary":"Ordering food is not supported"}
        """
}
