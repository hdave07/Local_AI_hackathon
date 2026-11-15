import FlowCore
import Foundation

/// Checks a validated model intent against what the user actually said.
///
/// Bonsai 2B copies values from its prompt examples (T-002: "tomorrow 4 pm" for
/// "friday afternoon") and guesses targets for pronouns ("open it" → Safari). Every
/// slot the model fills must therefore be *grounded*: its content words must occur in
/// the utterance or in the task context. Ungrounded answers become a question.
enum Guard {
    /// Words a time slot may add without being spoken (the adapter shows its interpretation).
    static let timeExtras: Set<String> = ["am", "pm"]
    static let mailNouns: Set<String> = ["email", "emails", "mail", "inbox", "message", "messages", "reply", "draft"]
    static let personPronouns: Set<String> = ["her", "him", "them", "his", "their", "hers", "theirs"]

    static func slotValues(_ action: FlowAction) -> [String] {
        switch action {
        case .createDraft(let r, _): [r]  // content may legitimately mention "her"
        case .readMessage(let q): [q]
        case .queryCalendar(let t): [t]
        case .clickElement(let l), .focus(let l): [l]
        default: []
        }
    }

    static let searchCues: Set<String> = [
        "find", "search", "look", "show", "open", "read", "where", "check", "get", "pull", "bring", "latest", "last",
        "newest", "see", "view", "any", "have",
    ]
    static let sizeWords: [ResizeChange: Set<String>] = [
        .wider: ["wider", "wide", "width"], .narrower: ["narrower", "narrow", "thinner", "thin"],
        .taller: ["taller", "tall", "height"], .shorter: ["shorter", "short"],
        .larger: ["bigger", "larger", "big", "large", "grow"], .smaller: ["smaller", "small", "shrink"],
    ]
    static let positionWords: [WindowPosition: Set<String>] = [
        .leftHalf: ["left"], .rightHalf: ["right"],
        .maximize: ["maximize", "maximise", "max", "full", "fullscreen", "expand", "maximized"],
        .center: ["center", "centre", "middle"],
    ]
    static let calendarQuestionCues: Set<String> = ["do", "am", "is", "are", "when", "what", "anything", "any", "have", "whats"]
    static let calendarNouns: Set<String> = [
        "calendar", "schedule", "meeting", "meetings", "event", "events", "free", "busy", "available", "appointment",
    ]

    /// Returns nil when the intent is acceptable, else the clarification to ask instead.
    static func check(_ intent: Intent, utterance: String, context: ConversationContext) -> RuleHit? {
        guard let action = intent.action else { return nil }  // clarification / unsupported pass through
        let spoken = Set(Words.tokens(utterance))
        // A person pronoun inside a model slot is an unresolved reference ("her lost email").
        if !Set(slotValues(action).flatMap(Words.tokens)).isDisjoint(with: personPronouns) {
            return RuleHit(intent: Make.ask("Who do you mean?"), stage: .guarded)
        }
        let known = spoken.union(context.recentPeople.flatMap(Words.tokens))
            .union(context.openMessage.map(Words.tokens) ?? [])
            .union(context.lastEditedText.map(Words.tokens) ?? [])

        func grounded(_ value: String, extras: Set<String> = []) -> Bool {
            let tokens = Words.contentTokens(value)
            return !tokens.isEmpty && tokens.allSatisfy { known.contains($0) || extras.contains($0) }
        }
        func appGrounded(_ app: KnownApp) -> Bool {
            !app.groundingWords.isDisjoint(with: spoken) || context.activeApp == app
        }
        func windowGrounded(_ w: WindowTarget) -> Bool {
            if case .app(let app) = w { return appGrounded(app) }
            return true
        }
        func ask(_ q: String, _ pending: PendingQuestion? = nil) -> RuleHit {
            RuleHit(intent: Make.ask(q), stage: .guarded, pending: pending)
        }

        switch action {
        case .activateApp(let app):
            return appGrounded(app) ? nil : ask(Make.whichApp, .app(then: .activate))
        case .tileWindows(let l, let r):
            return appGrounded(l) && appGrounded(r) ? nil : ask("Which two apps should go side by side?")
        case .moveWindow(let w, let p):
            guard !spoken.isDisjoint(with: positionWords[p] ?? []) else { return ask(Make.wherePosition, .position(window: w)) }
            return windowGrounded(w) ? nil : ask(Make.whichApp, .app(then: .move(p)))
        case .resizeWindow(let w, let c):
            // "Maximize Ige" must not become "make it larger": the size word has to be spoken.
            guard !spoken.isDisjoint(with: sizeWords[c] ?? []) else { return ask("Wider, narrower, taller, shorter, bigger or smaller?") }
            return windowGrounded(w) ? nil : ask(Make.whichApp, .app(then: .resize(c)))
        case .clickElement(let label), .focus(let label):
            // FlowAX presses whatever it resolves; a model "click Send" must use the send flow.
            if let hit = Rules.consequentialClick(label) { return RuleHit(intent: hit.intent, stage: .guarded) }
            return grounded(label) ? nil : ask("Which button or field?")
        case .scroll(let direction):
            // The direction itself must be spoken ("scroll after bit" is not "scroll down").
            return spoken.contains(direction.rawValue) ? nil : ask("Scroll up or down?")
        case .insertText(let text):
            return grounded(text) ? nil : ask("What should I type?")
        case .replaceText(let old, let new):
            return grounded(old) && grounded(new) ? nil : ask("Which text should I change, and to what?")
        case .createDraft(let recipient, let content):
            let recipientWords = Words.tokens(recipient)
            if recipientWords.isEmpty || recipientWords.count > 3 || !Set(recipientWords).isDisjoint(with: mailNouns)
                || recipientWords.allSatisfy({ ConversationContext.nonNames.contains($0) })
                || !grounded(recipient)
            { return ask("Who should the message go to?", .person(candidates: [], then: .draft(content: ""))) }
            if !content.isEmpty, !grounded(content, extras: timeExtras) { return ask("What should the message say?") }
            return nil
        case .readMessage(let query):
            if !grounded(query) { return ask("Which email should I look for?") }
            // Finding or reading needs a find/read verb; "emailed them that friday works" is not a search.
            if spoken.isDisjoint(with: searchCues) { return ask("Do you want to find an email?") }
            if spoken.isDisjoint(with: mailNouns), !spoken.isDisjoint(with: calendarNouns) {
                return ask("Do you want to check your calendar or search your email?")
            }
            return nil
        case .queryCalendar(let time):
            // Mail-only wording must not become a calendar answer (T-002 email-search failures).
            if !spoken.isDisjoint(with: mailNouns), spoken.isDisjoint(with: calendarNouns) {
                return ask("Do you want to search your email or check your calendar?")
            }
            // A calendar query is a question about the schedule; "open the thing from
            // yesterday" mentions a time but asks nothing about the calendar.
            if spoken.isDisjoint(with: calendarNouns), spoken.isDisjoint(with: calendarQuestionCues) {
                return ask("Do you want to check your calendar?")
            }
            guard grounded(time, extras: timeExtras), Words.tokens(time).contains(where: isTimeWord) else {
                return ask("Which day or time should I check?", .calendarTime)
            }
            // Completeness: every spoken time word must survive (V2 once turned
            // "anything at four tomorrow" into "tomorrow", silently dropping the hour).
            let kept = Set(Words.tokens(time))
            let dropped = spoken.filter { isTimeWord($0) && !kept.contains($0) }
            return dropped.isEmpty ? nil : ask("Which day or time should I check?", .calendarTime)
        case .showCalendar(let day):
            // Showing a day is navigation: it needs the calendar mentioned and a spoken day.
            if spoken.isDisjoint(with: calendarNouns) { return ask("Do you want to see your calendar?") }
            guard grounded(day, extras: timeExtras), Words.tokens(day).contains(where: isTimeWord) else {
                return ask("Which day should I show?")
            }
            return nil
        case .requestSend:
            return spoken.contains("send") ? nil : ask("Do you want to send the current draft?")
        case .requestReview:
            return spoken.isDisjoint(with: ["review", "check", "show", "read", "see", "look"]) ? ask("Do you want to review the current draft?") : nil
        }
    }

    static let timeVocabulary: Set<String> = [
        "today", "tonight", "tomorrow", "yesterday", "morning", "afternoon", "evening", "night", "noon", "midnight",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "weekend", "week", "next",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december",
    ]

    /// Tokens are already normalized (number words → digits, "12th" → "12").
    /// Asks about the schedule and mentions no mail ("do I have anything at four", "am I busy").
    static func soundsLikeCalendar(_ utterance: String) -> Bool {
        let w = Set(Words.tokens(utterance))
        guard w.isDisjoint(with: mailNouns) else { return false }
        let vague = !w.isDisjoint(with: ["anything", "something"])
        return !w.isDisjoint(with: calendarNouns) || (vague && (w.contains("have") || w.contains(where: isTimeWord)))
    }

    static func isTimeWord(_ token: String) -> Bool {
        timeVocabulary.contains(token) || (!token.isEmpty && token.allSatisfy(\.isNumber))
    }

    // MARK: Times without a colon

    /// "330", "3.30" (no am/pm) in a content or calendar slot: ASR dropped the colon, or the
    /// user meant the number. Asking costs one "yes"; guessing could silently change a time.
    static let colonlessTime = Rx(#"(.*?)\b(1[0-2]|[1-9])\.?([0-5][0-9])\b(.*)"#)

    static func proposeTime(_ text: String) -> String? {
        guard let m = colonlessTime.match(text), let h = m[1], let mm = m[2] else { return nil }
        let before = m[0] ?? "", after = m[3] ?? ""
        if before.hasSuffix(":") || after.hasPrefix(":") || before.hasSuffix(".") { return nil }
        if after.range(of: #"^\.?[0-9]"#, options: .regularExpression) != nil { return nil }  // part of a longer number
        return before + h + ":" + mm + after
    }

    /// The same action with a colon-less time rewritten as H:MM, if any slot has one.
    static func timeCorrected(_ action: FlowAction) -> FlowAction? {
        switch action {
        case .replaceText(let old, let new):
            if let n = proposeTime(new) { return .replaceText(old: old, new: n) }
            if let o = proposeTime(old) { return .replaceText(old: o, new: new) }
            return nil
        case .insertText(let t):
            return proposeTime(t).map(FlowAction.insertText)
        case .createDraft(let r, let c):
            return proposeTime(c).map { .createDraft(recipient: r, content: $0) }
        case .queryCalendar(let t):
            return proposeTime(t).map(FlowAction.queryCalendar)
        default:
            return nil
        }
    }

    static func confirmTime(_ intent: Intent) -> RuleHit? {
        guard let action = intent.action, let corrected = timeCorrected(action) else { return nil }
        let shown = ActionText.differingTime(action, corrected) ?? "that time"
        return RuleHit(
            intent: Make.ask("Did you mean \(shown)? Say yes, or no to keep it as heard."), stage: .clarify,
            pending: .confirm(proposed: corrected, otherwise: action, kind: intent.kind))
    }

    /// A validator rejection caused by a missing argument becomes a targeted question.
    static func question(for error: ClassificationError, rawContent: String?) -> RuleHit? {
        let action: String?
        switch error {
        case .unsupportedTarget(let a, let target) where target == "(empty)" || target.isEmpty:
            action = a
        case .schemaViolation(let why) where why.contains("is empty"):
            action = rawContent.flatMap(actionName(in:))
        case .inconsistentIntent(let why) where why.contains("requires an action"):
            return RuleHit(intent: Make.ask("I didn't catch what to do. Could you say it another way?"), stage: .guarded)
        default:
            return nil
        }
        let q: String
        switch action {
        case "activate_app": q = Make.whichApp
        case "tile_windows": q = "Which two apps should go side by side?"
        case "move_window": q = Make.wherePosition
        case "resize_window": q = "Wider, narrower, taller, shorter, bigger or smaller?"
        case "click_element", "focus": q = "Which button or field?"
        case "insert_text": q = "What should I type?"
        case "replace_text": q = "Which text should I change, and to what?"
        case "create_draft": q = "Who should the message go to, and what should it say?"
        case "read_message": q = "Which email should I look for?"
        case "query_calendar": return RuleHit(intent: Make.ask("Which day or time should I check?"), stage: .guarded, pending: .calendarTime)
        default: q = "I didn't catch that. Could you say it another way?"
        }
        return RuleHit(intent: Make.ask(q), stage: .guarded)
    }

    static func actionName(in raw: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
        return object["action"] as? String
    }
}

enum ActionText {
    /// The corrected H:MM time, for the question text.
    static func differingTime(_ original: FlowAction, _ corrected: FlowAction) -> String? {
        let text: String
        switch corrected {
        case .replaceText(let o, let n):
            if case .replaceText(let o0, _) = original, o0 != o { text = o } else { text = n }
        case .insertText(let t): text = t
        case .createDraft(_, let c): text = c
        case .queryCalendar(let t): text = t
        default: return nil
        }
        guard let r = text.range(of: #"\b(1[0-2]|[1-9]):[0-5][0-9]\b"#, options: .regularExpression) else { return nil }
        return String(text[r])
    }
}
