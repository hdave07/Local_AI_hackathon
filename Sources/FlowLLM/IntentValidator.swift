import FlowCore
import Foundation

/// Converts untrusted model text into a typed `Intent`, or rejects it.
///
/// Rules: the content must be a single JSON object with exactly the schema's
/// string fields (no extras, no missing keys, no markdown fences); `kind` and
/// `action` must come from the allowlists; each action's arguments are parsed
/// into strict typed values; kind/action combinations must be consistent.
public enum IntentValidator {
    static let maxContentBytes = 8_192
    static let maxLabelLength = 100
    static let maxShortTextLength = 200
    static let maxLongTextLength = 2_000

    public static func validate(_ content: String, modelID: String) throws(ClassificationError) -> Intent {
        let fields = try decodeFields(content)

        let kindRaw = fields["kind"]!
        guard let kind = IntentKind(rawValue: kindRaw), IntentKind.modelEmittable.contains(kind) else {
            throw .schemaViolation("kind “\(kindRaw)” is not allowed")
        }
        let actionRaw = fields["action"]!
        let target = fields["target"]!.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = fields["detail"]!.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = try text(fields["summary"]!, field: "summary", max: maxShortTextLength, allowEmpty: true)

        let action: FlowAction?
        if actionRaw == IntentSchema.noAction {
            action = nil
        } else if let type = ActionType(rawValue: actionRaw) {
            action = try buildAction(type, target: target, detail: detail)
        } else {
            throw .unsupportedAction(actionRaw)
        }

        try checkConsistency(kind: kind, action: action)

        let fallbackSummary = action.map { "\($0.type.rawValue): \($0.targetDescription)" } ?? kind.rawValue
        return Intent(
            kind: kind, action: action,
            summary: summary.isEmpty ? fallbackSummary : summary,
            source: .model(id: modelID))
    }

    // MARK: - Strict decoding

    static func decodeFields(_ content: String) throws(ClassificationError) -> [String: String] {
        let data = Data(content.utf8)
        guard data.count <= maxContentBytes else { throw .malformedJSON("response too large") }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .malformedJSON("not parseable JSON")
        }
        guard let object = parsed as? [String: Any] else {
            throw .malformedJSON("top level is not a JSON object")
        }
        let expected = Set(IntentSchema.fields)
        let keys = Set(object.keys)
        if let extra = keys.subtracting(expected).sorted().first {
            throw .schemaViolation("unexpected field “\(extra)”")
        }
        if let missing = expected.subtracting(keys).sorted().first {
            throw .schemaViolation("missing field “\(missing)”")
        }
        var result: [String: String] = [:]
        for key in IntentSchema.fields {
            guard let value = object[key] as? String else {
                throw .schemaViolation("field “\(key)” must be a string")
            }
            result[key] = value
        }
        return result
    }

    // MARK: - Per-action arguments

    static func buildAction(_ type: ActionType, target: String, detail: String) throws(ClassificationError) -> FlowAction {
        func badTarget(_ value: String) -> ClassificationError {
            .unsupportedTarget(action: type.rawValue, target: value.isEmpty ? "(empty)" : value)
        }

        switch type {
        case .activateApp:
            guard let app = KnownApp.parse(target) else { throw badTarget(target) }
            return .activateApp(app)

        case .tileWindows:
            let parts = target
                .replacingOccurrences(of: " and ", with: ",")
                .replacingOccurrences(of: "&", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let apps = parts.compactMap(KnownApp.parse)
            guard parts.count == 2, apps.count == 2, apps[0] != apps[1] else { throw badTarget(target) }
            return .tileWindows(left: apps[0], right: apps[1])

        case .moveWindow:
            let window = try windowTarget(target, type: type)
            guard let position = WindowPosition.parse(detail) else { throw badTarget(detail) }
            return .moveWindow(window, position)

        case .resizeWindow:
            let window = try windowTarget(target, type: type)
            guard let change = ResizeChange.parse(detail) else { throw badTarget(detail) }
            return .resizeWindow(window, change)

        case .clickElement:
            return .clickElement(label: try text(target, field: "target", max: maxLabelLength))

        case .focus:
            return .focus(label: try text(target, field: "target", max: maxLabelLength))

        case .scroll:
            guard let direction = ScrollDirection.parse(detail.isEmpty ? target : detail) else {
                throw badTarget(detail.isEmpty ? target : detail)
            }
            return .scroll(direction)

        case .insertText:
            // Small models sometimes put the text in `target`; accept that only when detail is empty.
            let value = detail.isEmpty ? target : detail
            return .insertText(try text(value, field: "detail", max: maxLongTextLength))

        case .replaceText:
            let old = try text(target, field: "target", max: maxShortTextLength)
            let new = try text(detail, field: "detail", max: maxShortTextLength)
            guard old != new else { throw .inconsistentIntent("replacement is identical to the original") }
            return .replaceText(old: old, new: new)

        case .createDraft:
            let recipient = try text(target, field: "target", max: maxLabelLength)
            let content = try text(detail, field: "detail", max: maxLongTextLength, allowEmpty: true)
            return .createDraft(recipient: recipient, content: content)

        case .readMessage:
            return .readMessage(query: try text(target, field: "target", max: maxShortTextLength))

        case .queryCalendar:
            return .queryCalendar(timeExpression: try text(target, field: "target", max: maxLabelLength))

        case .showCalendar:
            return .showCalendar(dateExpression: try text(target, field: "target", max: maxLabelLength))

        case .requestReview:
            return .requestReview

        case .requestSend:
            return .requestSend
        }
    }

    static func windowTarget(_ raw: String, type: ActionType) throws(ClassificationError) -> WindowTarget {
        switch raw.lowercased() {
        case "", "active", "this", "current", "this window", "active window", "current window":
            return .active
        default:
            guard let app = KnownApp.parse(raw) else {
                throw .unsupportedTarget(action: type.rawValue, target: raw)
            }
            return .app(app)
        }
    }

    /// Bounded, printable text argument.
    static func text(
        _ value: String, field: String, max: Int, allowEmpty: Bool = false
    ) throws(ClassificationError) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !allowEmpty { throw .schemaViolation("“\(field)” is empty") }
        guard trimmed.count <= max else { throw .schemaViolation("“\(field)” is too long") }
        let disallowed = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\n\t"))
        guard trimmed.unicodeScalars.allSatisfy({ !disallowed.contains($0) }) else {
            throw .schemaViolation("“\(field)” contains control characters")
        }
        return trimmed
    }

    // MARK: - Kind/action consistency

    static func checkConsistency(kind: IntentKind, action: FlowAction?) throws(ClassificationError) {
        switch kind {
        case .clarification, .unsupported:
            if action != nil { throw .inconsistentIntent("\(kind.rawValue) must not carry an action") }
        case .edit, .dictation, .direct, .task:
            guard let action else { throw .inconsistentIntent("\(kind.rawValue) requires an action") }
            if kind == .edit, !action.type.isTextAction {
                throw .inconsistentIntent("edit cannot use \(action.type.rawValue)")
            }
            if kind == .dictation, action.type != .insertText {
                throw .inconsistentIntent("dictation can only insert text")
            }
        case .control, .confirmation:
            throw .schemaViolation("kind “\(kind.rawValue)” is reserved for deterministic routing")
        }
    }
}
