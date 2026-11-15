import FlowCore
import Foundation
import FlowText

/// Which stage of the router produced a decision.
public enum RouteStage: String, Sendable, Equatable {
    /// stop / cancel / stop dictation (FlowCore `DeterministicRouter`).
    case control
    /// Answer to a pending clarification question.
    case followUp = "follow_up"
    /// Deterministic grammar for explicit, simple commands.
    case fastPath = "fast_path"
    /// Deterministic reference resolution against `ConversationContext`.
    case context
    /// Deterministic clarification or decline (missing/ambiguous information).
    case clarify
    /// Numbered-overlay phrases (show/hide numbers, choose N): deterministic, never the model.
    case overlay
    /// Bonsai via LM Studio, validated and grounded.
    case model
    /// Bonsai answered, but the answer failed a grounding/consistency guard; replaced by a question.
    case guarded
}

/// A routing outcome before it becomes a `RoutingDecision`.
struct RuleHit {
    let intent: Intent
    let stage: RouteStage
    var pending: PendingQuestion? = nil
}

enum Make {
    static func intent(_ kind: IntentKind, _ action: FlowAction, _ summary: String) -> Intent {
        Intent(kind: kind, action: action, summary: summary, source: .deterministic)
    }

    static func ask(_ question: String) -> Intent {
        Intent(kind: .clarification, summary: question, source: .deterministic)
    }

    static func decline(_ message: String) -> Intent {
        Intent(kind: .unsupported, summary: message, source: .deterministic)
    }

    static let whichApp = "Which app? You can name any app on this Mac."
    static let wherePosition = "Where should it go: left half, right half, center, or maximize?"
}

/// Deterministic rules. Every pattern must match the *whole* cleaned utterance, so a
/// command embedded in a longer sentence falls through to the model.
enum Rules {
    // MARK: Building blocks

    static let pronoun = #"(?:it|that|this|that one|this one)"#
    static let personPronoun = #"(her|him|them|that person)"#
    static let windowPhrase = #"(.+?)"#
    static let positionWords = #"(left|right)(?:\s+(?:half|side))?(?:\s+of\s+the\s+screen)?"#
    static let degree = #"(?:(?:a\s+)?(?:little|bit|tad|little bit|lot)\s+|slightly\s+|much\s+|a\s+bit\s+)?"#
    static let sizes = #"(wider|narrower|taller|shorter|bigger|larger|smaller)"#

    /// "this window", "the window", "the mail window", "mail", "the notes app". Pronouns excluded.
    static func window(_ phrase: String) -> WindowTarget? {
        let p = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        if ["this window", "the window", "current window", "the current window", "active window", "the active window",
            "my window"].contains(p) {
            return .active
        }
        if let app = KnownApp.fromPhrase(p) { return .app(app) }
        return nil
    }

    static func isPronounPhrase(_ phrase: String) -> Bool {
        ["it", "that", "this", "that one", "this one", "that window", "it's window"].contains(phrase.lowercased())
    }

    /// Recipients that must not be treated as a person name.
    static func isPersonName(_ s: String) -> Bool {
        let w = s.lowercased()
        return !ConversationContext.nonNames.contains(w) && w.range(of: #"^[a-z][a-z'-]*(\.[a-z][a-z'-]*)*$"#, options: .regularExpression) != nil
    }

    // MARK: Numbered overlay

    /// Not representable in `FlowAction` yet (needs the shared contract in ADR 0004 / Track A
    /// ADR 0003 §2). Recognized deterministically so the model never guesses at them.
    static func overlay(_ s: String) -> RuleHit? {
        let lower = s.lowercased()
        if showNumbers.match(lower) != nil || showClickable.match(lower) != nil {
            return RuleHit(intent: Make.intent(.direct, .showNumbers, "Show numbers on what I can click"), stage: .overlay)
        }
        if hideNumbers.match(lower) != nil {
            return RuleHit(intent: Make.intent(.direct, .hideNumbers, "Hide the numbers"), stage: .overlay)
        }
        if let m = chooseNumber.match(lower) ?? clickNumber.match(lower), let n = m[0].flatMap(Self.number) {
            return RuleHit(intent: Make.intent(.direct, .chooseNumber(n), "Choose number \(n)"), stage: .overlay)
        }
        return nil
    }

    static let showClickable = Rx(#"(?:show|tell|give)(?:\s+me)?\s+(?:what|everything|the things|things)\s+(?:i\s+)?can\s+(?:click|press|select|tap)(?:\s+on)?(?:\s+here)?|(?:show|display|list)(?:\s+me)?\s+(?:the\s+)?(?:numbered\s+(?:options|buttons|controls|items)|(?:available\s+)?(?:buttons|controls|options)(?:\s+(?:here|in (?:the|this) (?:current\s+)?(?:app|window)))?)"#)
    static let clickNumber = Rx(#"(?:click|press|tap|select|pick|choose|hit)\s+(?:on\s+)?number\s+"# + numberWord)

    static func number(_ word: String) -> Int? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                     "eleven": 11, "twelve": 12]
        return Int(word) ?? words[word.lowercased()]
    }

    /// Words in a click/focus label that make the press consequential.
    static func consequentialClick(_ label: String) -> RuleHit? {
        let words = Set(Words.tokens(label))
        if words.contains("send") {
            return RuleHit(intent: Make.intent(.direct, .requestSend, "Send the current draft (needs confirmation)"), stage: .fastPath)
        }
        if !words.isDisjoint(with: ["delete", "trash", "discard", "remove", "erase"]) {
            return RuleHit(intent: Make.decline("Deleting isn't supported yet."), stage: .clarify)
        }
        return nil
    }

    // MARK: Unsupported verbs (no such action in the allowlist)

    static let unsupportedVerbs = Rx(#"(?:force\s+)?(close|quit|delete|remove|trash|erase|discard|shut|kill|uninstall)\b.*"#)

    static func unsupported(_ s: String) -> RuleHit? {
        guard let m = unsupportedVerbs.match(s), let verb = m[0]?.lowercased() else { return nil }
        switch verb {
        case "quit", "kill", "shut":
            // Quitting can discard unsaved work; Flow never quits or force-quits apps.
            return RuleHit(intent: Make.decline("I can't quit apps. I can close a window instead: say “close this window” or “close Notes”."),
                           stage: .clarify)
        case "close":
            return RuleHit(intent: Make.decline("I couldn't tell which window to close. Say “close this window”, or name the app, like “close Notes”."),
                           stage: .clarify)
        default:
            return RuleHit(intent: Make.decline("Deleting isn't supported yet."), stage: .clarify)
        }
    }

    // MARK: Apps and windows by voice (ADR 0011)

    /// App and window commands that may run while a question is open without abandoning it.
    static func isQuickAppCommand(_ s: String) -> Bool {
        if let hit = windowControl(s, .empty), let action = hit.intent.action {
            switch action {
            case .activateApp, .minimizeWindow, .restoreWindow, .listWindows: return true
            default: return false
            }
        }
        if let m = activate.match(s), let phrase = m[0], KnownApp.fromPhrase(phrase) != nil { return true }
        return false
    }

    static let closeWindowRx = Rx(#"close\s+(.+?)"#)
    static let bringBackRx = Rx(#"bring\s+(?:the\s+)?(.+?)\s+back(?:\s+up)?"#)
    static let minimizeRx = Rx(#"minimi[sz]e(?:\s+(.+?))?"#)
    static let restoreRx = Rx(#"(?:restore|unminimi[sz]e|un-minimi[sz]e|bring back)(?:\s+(.+?))?"#)
    static let goBackRx = Rx(#"(?:go|switch|get|take me|jump|flip)\s+back(?:\s+to\s+(?:the\s+)?(.+?))?(?:\s+again)?|(?:return|back)\s+to\s+(?:the\s+)?(.+?)"#)
    static let bringFrontRx = Rx(#"(?:bring|put|move)\s+(?:the\s+)?(.+?)\s+(?:to the front|to front|in front|forward|up front|on top|to the top)"#)
    static let listWindowsRx = Rx(#"(?:(?:show|list|tell)(?:\s+me)?\s+(?:all\s+)?(?:of\s+)?(?:my\s+|the\s+)?(?:open\s+)?windows(?:\s+(?:that are\s+|are\s+)?open)?|what\s+windows\s+(?:are|do i have)\s+open|which\s+windows\s+are\s+open|what(?:'s| is)\s+open)"#)

    /// The window a phrase names: "this window" → the active window; an app → that app's window;
    /// "it" / "that window" → the window Flow last acted on (or the active app's).
    static func windowTarget(_ phrase: String?, _ ctx: ConversationContext) -> WindowTarget? {
        guard var p = phrase?.lowercased().trimmingCharacters(in: .whitespaces), !p.isEmpty else { return .active }
        for prefix in ["the ", "my "] where p.hasPrefix(prefix) { p = String(p.dropFirst(prefix.count)) }
        for suffix in [" window", " app", " application"] where p.hasSuffix(suffix) && p.count > suffix.count {
            p = String(p.dropLast(suffix.count))
        }
        // "this window" / "the window": what the user is looking at now.
        if ["window", "current", "active", "front", "frontmost", "focused", "this", "this one", "current one"].contains(p) {
            return .active
        }
        // "it" / "that window": the window Flow last acted on. Without one, don't guess.
        if ["it", "that", "that one", "the last one", "last", "last one"].contains(p) {
            guard let app = ctx.selectedWindow?.app ?? ctx.activeApp else { return nil }
            return .app(app)
        }
        if let app = KnownApp.fromPhrase(p) { return .app(app) }
        return nil
    }

    static func windowControl(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
        let lower = s.lowercased()
        if listWindowsRx.match(lower) != nil {
            return hit(.direct, .listWindows, "Show open windows")
        }
        if let m = goBackRx.match(s) {
            if let phrase = m[0] ?? m[1] {
                guard let app = KnownApp.fromPhrase(phrase.lowercased()) else { return nil }
                return hit(.direct, .activateApp(app), "Go back to \(app.rawValue)")
            }
            guard let app = ctx.previousApp else {
                return RuleHit(intent: Make.ask("Which app should I go back to?"), stage: .clarify, pending: .app(then: .activate))
            }
            return RuleHit(intent: Make.intent(.direct, .activateApp(app), "Go back to \(app.rawValue)"), stage: .context)
        }
        if let m = bringFrontRx.match(s), let phrase = m[0], let app = KnownApp.fromPhrase(phrase.lowercased()) {
            return hit(.direct, .activateApp(app), "Bring \(app.rawValue) to the front")
        }
        if let m = closeWindowRx.match(s) {
            // "close the draft/reply" is handled earlier (draftDiscard); anything else unknown falls through.
            guard let target = windowTarget(m[0], ctx) else { return nil }
            return RuleHit(intent: Make.intent(.direct, .closeWindow(target), "Close \(target.displayName)"), stage: .fastPath)
        }
        if let m = minimizeRx.match(s) {
            guard let target = windowTarget(m[0], ctx) else { return nil }
            return RuleHit(intent: Make.intent(.direct, .minimizeWindow(target), "Minimize \(target.displayName)"), stage: .fastPath)
        }
        if let m = bringBackRx.match(s), let target = windowTarget(m[0], ctx) {
            return RuleHit(intent: Make.intent(.direct, .restoreWindow(target), "Restore \(target.displayName)"), stage: .fastPath)
        }
        if let m = restoreRx.match(s) {
            // Bare "restore": the window Flow last acted on, if any.
            let phrase = m[0] ?? (ctx.selectedWindow?.app != nil ? "it" : nil)
            guard let target = windowTarget(phrase, ctx) else { return nil }
            return RuleHit(intent: Make.intent(.direct, .restoreWindow(target), "Restore \(target.displayName)"), stage: .fastPath)
        }
        return nil
    }

    // MARK: Fast path (explicit targets only)

    static let activate = Rx(#"(?:open|launch|start|switch to|switch over to|change to|go to|go over to|bring up|show(?: me)?|pull up|focus on|focus|activate|jump to|take me to)\s+(?:the\s+)?(.+?)(?:\s+app)?"#)
    /// "and"; ASR often hears "end" between two app names.
    static let and = #"(?:and|end)"#
    static let tileVerb = Rx(#"(?:tile|split)\s+(.+?)\s+"# + and + #"\s+(.+?)(?:\s+(?:side by side|next to each other|together))?"#)
    static let tilePhrase = Rx(#"(?:(?:put|place|show|arrange|set)\s+)?(.+?)\s+"# + and + #"\s+(.+?)\s+(?:side by side|next to each other)"#)
    static let tileSides = Rx(#"(?:(?:put|place|move)\s+)?(.+?)\s+on the (left|right)(?: side)?,?\s+"# + and + #"\s+(?:(?:put|place)\s+)?(.+?)\s+on the (left|right)(?: side)?"#)
    static let moveSide = Rx(#"(?:move|put|snap|send|place|push)\s+"# + windowPhrase + #"\s+(?:to\s+|on\s+|onto\s+)?(?:the\s+)?"# + positionWords)
    static let maximize = Rx(#"(?:maximize|maximise|expand)\s+"# + windowPhrase)
    static let fullScreen = Rx(#"make\s+"# + windowPhrase + #"\s+(?:full ?screen|full size|maximized|maximised)"#)
    static let center = Rx(#"(?:center|centre)\s+"# + windowPhrase)
    static let moveCenter = Rx(#"(?:move|put|place)\s+"# + windowPhrase + #"\s+(?:to\s+|in\s+)?(?:the\s+)?(?:center|centre|middle)"#)
    static let resize = Rx(#"make\s+"# + windowPhrase + #"\s+"# + degree + sizes)
    static let scrollDir = Rx(#"scroll\s+(up|down)(?:\s+(?:a\s+(?:bit|little)|a little bit|some|more|slightly|again))?"#)
    static let scrollEnd = Rx(#"(?:scroll|go|jump|move)\s+(?:all the way\s+)?(?:to\s+|up to\s+|down to\s+)?(?:the\s+)?(top|bottom)(?:\s+of\s+(?:the\s+)?(?:page|window|list|message|email|screen))?"#)
    static let page = Rx(#"page\s+(up|down)"#)
    static let send = Rx(#"send(?:\s+(?:it|this|that|the|my))?(?:\s+(?:draft|email|e-mail|message|reply|response|mail))?(?:\s+now)?"#)
    /// "send my reply to Sarah", "send it to sarah": a named recipient must match the open draft.
    static let sendNamed = Rx(#"send(?:\s+(?:it|this|that|the|my))?(?:\s+(?:draft|email|e-mail|message|reply|response|mail))?\s+to\s+([a-z][a-z'.-]*(?:\s+[a-z][a-z'.-]*)?)(?:\s+now)?"#)
    static let review = Rx(#"(?:review|show me|let me (?:see|review|check)|read(?: back)?(?: me)?|check)\s+(?:the|my|this)\s+(?:draft|reply|response|email draft|message draft)(?:\s+before sending)?"#)

    // Mail search: explicit mail noun, never a calendar phrase.
    static let searchMailFor = Rx(#"(?:search|look through|check)\s+(?:my\s+|the\s+)?(?:mail|email|e-mail|inbox|messages)\s+for\s+(.+)"#)
    static let searchMail = Rx(#"(?:find|search for|look for|look up|show(?: me)?|open|pull up|get|read|bring up|go to)\s+((?:(?:the|my|an?)\s+)?(?:(?:latest|last|newest|most recent|recent|new|unread|first)\s+)?(?:email|e-mail|mail|message|messages|emails)\b.*)"#)
    static let searchMailPossessive = Rx(#"(?:find|search for|look for|look up|show(?: me)?|open|pull up|get|read)\s+((?:the\s+)?([a-z][a-z.-]*)'s\s+(?:(?:latest|last|newest|most recent|recent|new|unread)\s+)?(?:email|e-mail|mail|message)s?\b.*)"#)

    // Showing a day in Calendar (navigation, read-only): "show me tomorrow on my calendar".
    static let showCalendarDay = Rx(#"(?:show|open|bring up|pull up|go to|display|take me to)\s+(?:me\s+)?(?:(?:my|the)\s+)?(?:calendar\s+(?:for|on|to|at)\s+(.+)|(?!what\b)(.+?)\s+(?:on|in)\s+(?:my\s+|the\s+)?calendar)"#)
    // Calendar queries.
    static let calendar = Rx(#"(?:(?:check|see|tell me|find out)\s+(?:whether|if)\s+)?(?:(?:do i|don't i|don't|do) have (?:anything|something|any meetings?|any events?|any plans|plans|a meeting|meetings)(?:\s+(?:scheduled|planned|booked|on))?|i have (?:anything|something|any meetings?|any events?|any plans|plans)(?:\s+(?:scheduled|planned|booked|on))?|am i (?:free|busy|available)|i(?:'m| am) (?:free|busy|available)|is (?:anything|something|there anything|there something) (?:scheduled|planned|booked|on my (?:calendar|schedule))|what(?:'s| is) on my (?:calendar|schedule)|what do i have(?: on)?|check my (?:calendar|schedule)|is there anything on my (?:calendar|schedule)|what(?:'s| is) my schedule)(?:\s+(.+))?"#)

    // Drafting: verb + single-word name + optional connector + content (verbatim).
    /// "reply to X", "write to X", "send an email to X" need "to"; "email X", "message X", "answer X" do not.
    static let draftVerb = #"(?:(?:reply|respond|write back|write(?: an? (?:email|e-mail|message|note|reply))?|send (?:an? )?(?:email|e-mail|message|note|reply)|draft (?:an? )?(?:email|reply|message))\s+to|email|e-mail|message|answer)"#
    static let connector = #"(?:\s*[,:.]\s*|\s+)(?:(?:that|saying|to say|and say|and tell (?:her|him|them)|with)\s+)?"#
    /// A person's name: letters, apostrophes, hyphens; never a trailing period.
    static let name = #"([a-z][a-z'-]*(?:\.[a-z][a-z'-]*)*)"#
    static let draftNamed = Rx(draftVerb + #"\s+"# + name + #"(?:"# + connector + #"(.+))?"#)
    static let draftAsk = Rx(draftVerb + #"\s+"# + name + #"\s*[,.]?\s+(?:and\s+|to\s+)?((?:ask|asking)\b.+)"#)
    static let tell = Rx(#"(?:tell|let)\s+"# + name + #"(?:\s+know)?(?:\s*[,:.]\s*|\s+)(?:that\s+)?(.+)"#)

    // Editing.
    static let insert = Rx(#"(?:type|insert|enter|dictate)\s+(.+)"#)
    static let replace = Rx(#"(?:change|replace|swap)\s+(.+?)\s+(?:to|with|for|into)\s+(.+)"#)

    // UI navigation.
    // Labels are passed through as spoken ("the second Reply button"): FlowAX's
    // TargetReference parses articles, ordinals and role words itself (Track A ADR 0003 §3).
    static let click = Rx(#"(?:click|press|tap|hit|push)\s+(?:on\s+)?(.+)"#)
    static let focusField = Rx(#"(?:focus(?: on)?|go to|put the cursor in|click in(?:to)?|move to|select)\s+(.+?\s+(?:field|box|area))"#)
    static let focusVerb = Rx(#"(?:focus(?: on)?|put the cursor in)\s+(.+)"#)

    // Numbered overlay (FlowAX NavCommand.showNumbers / hideNumbers / choose).
    static let numberWord = #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
    static let showNumbers = Rx(#"(?:show|display)\s+(?:the\s+)?numbers(?:\s+for\s+.+)?|numbers"#)
    static let hideNumbers = Rx(#"(?:hide|remove|clear)\s+(?:the\s+)?numbers"#)
    static let chooseNumber = Rx(#"(?:(?:choose|pick|number|select number|go with)\s+)?(?:number\s+)?"# + numberWord)

    static func fastPath(_ s: String) -> RuleHit? {
        // Window and app commands with explicit targets.
        if let m = tileSides.match(s), let a = m[0].flatMap(KnownApp.fromPhrase), let sa = m[1]?.lowercased(),
            let b = m[2].flatMap(KnownApp.fromPhrase), let sb = m[3]?.lowercased(), sa != sb, a != b
        {
            let (left, right) = sa == "left" ? (a, b) : (b, a)
            return hit(.direct, .tileWindows(left: left, right: right), "Tile \(left.rawValue) and \(right.rawValue)")
        }
        for rule in [tileVerb, tilePhrase] {
            if let m = rule.match(s), let a = m[0].flatMap(KnownApp.fromPhrase), let b = m[1].flatMap(KnownApp.fromPhrase), a != b {
                return hit(.direct, .tileWindows(left: a, right: b), "Tile \(a.rawValue) and \(b.rawValue)")
            }
        }
        if let m = moveSide.match(s), let phrase = m[0], let w = window(phrase), let side = m[1]?.lowercased() {
            let position: WindowPosition = side == "left" ? .leftHalf : .rightHalf
            return hit(.direct, .moveWindow(w, position), "Move \(w.displayName) to the \(side) half")
        }
        for rule in [maximize, fullScreen] {
            if let m = rule.match(s), let phrase = m[0], let w = window(phrase) {
                return hit(.direct, .moveWindow(w, .maximize), "Maximize \(w.displayName)")
            }
        }
        for rule in [center, moveCenter] {
            if let m = rule.match(s), let phrase = m[0], let w = window(phrase) {
                return hit(.direct, .moveWindow(w, .center), "Center \(w.displayName)")
            }
        }
        if let m = resize.match(s), let phrase = m[0], let w = window(phrase), let change = m[1].flatMap(ResizeChange.parse) {
            return hit(.direct, .resizeWindow(w, change), "Make \(w.displayName) \(change.rawValue)")
        }
        if let m = activate.match(s), let phrase = m[0], let app = KnownApp.fromPhrase(phrase) {
            return hit(.direct, .activateApp(app), "Open \(app.rawValue)")
        }

        // Scrolling.
        if let m = scrollDir.match(s) ?? page.match(s), let d = m[0].flatMap(ScrollDirection.parse) {
            return hit(.direct, .scroll(d), "Scroll \(d.rawValue)")
        }
        if let m = scrollEnd.match(s), let d = m[0].flatMap(ScrollDirection.parse) {
            return hit(.direct, .scroll(d), "Scroll to the \(d.rawValue)")
        }

        // Draft review / send (the executor still requires review + explicit confirmation).
        if review.match(s) != nil { return hit(.direct, .requestReview, "Review the current draft") }
        if send.match(s) != nil { return hit(.direct, .requestSend, "Send the current draft (needs confirmation)") }

        // Mail search vs calendar: decided by explicit nouns, never by the model alone.
        if let m = searchMailFor.match(s), let q = m[0] {
            return hit(.direct, .readMessage(query: q), "Search mail for “\(q)”")
        }
        if let m = searchMailPossessive.match(s), let q = m[0], let name = m[1], isPersonName(name) {
            return hit(.direct, .readMessage(query: strip(q)), "Find \(name)'s email")
        }
        if let m = searchMail.match(s), let q = m[0] {
            return hit(.direct, .readMessage(query: strip(q)), "Find “\(strip(q))”")
        }
        if let m = showCalendarDay.match(s), let day = (m[0] ?? m[1])?.trimmingCharacters(in: .whitespaces), !day.isEmpty {
            return hit(.direct, .showCalendar(dateExpression: day), "Show \(day) in Calendar")
        }
        if let m = calendar.match(s) {
            guard let time = m[0]?.trimmingCharacters(in: .whitespaces), !time.isEmpty else {
                return RuleHit(intent: Make.ask("Which day or time should I check?"), stage: .clarify, pending: .calendarTime)
            }
            return hit(.direct, .queryCalendar(timeExpression: time), "Check calendar \(time)")
        }

        // Drafting with an explicit recipient; content is copied verbatim.
        if let hit = draft(s) { return hit }

        // Editing.
        if let m = insert.match(s), let text = m[0] {
            return hit(.edit, .insertText(text), "Type “\(text)”")
        }
        if let m = replace.match(s), let old = m[0], let new = m[1], !isPronounPhrase(old) {
            return hit(.edit, .replaceText(old: old, new: new), "Replace “\(old)” with “\(new)”")
        }

        // Navigation. A spoken "click send" goes through the send confirmation flow instead.
        if let m = focusField.match(s) ?? focusVerb.match(s), let label = m[0] {
            if let hit = consequentialClick(label) { return hit }
            return hit(.direct, .focus(label: label), "Focus “\(label)”")
        }
        if let m = click.match(s), let label = m[0], !isPronounPhrase(label) {
            // A spoken "click send" goes through review + confirmation, never a raw press.
            if let hit = consequentialClick(label) { return hit }
            return hit(.direct, .clickElement(label: label), "Click “\(label)”")
        }
        // "launch Spotify" when no such app is installed: say so plainly (never guess another app).
        if let m = launchUnknown.match(s), let phrase = m[0], Words.tokens(phrase).count <= 3,
           Set(Words.tokens(phrase)).isDisjoint(with: ["email", "emails", "mail", "message", "messages", "draft", "reply", "it", "that", "this", "calendar"]) {
            return RuleHit(intent: Make.decline("I couldn't find an app called “\(phrase)” on this Mac."), stage: .clarify)
        }
        return nil
    }

    static let launchUnknown = Rx(#"(?:launch|open|start|run|switch to|bring up|go to)\s+(?:the\s+)?(?:app\s+)?(.+?)(?:\s+app(?:lication)?)?"#)

    static func draft(_ s: String) -> RuleHit? {
        if let m = draftAsk.match(s), let name = m[0], isPersonName(name), let content = m[1] {
            return hit(.task, .createDraft(recipient: name, content: content), "Draft to \(name)")
        }
        if let m = draftNamed.match(s), let name = m[0] {
            let lower = name.lowercased()
            if lower == "all" || lower == "everyone" || lower == "everybody" {
                return RuleHit(intent: Make.ask("Reply to everyone on the thread? Say the recipient's name to reply to one person."), stage: .clarify)
            }
            if isPersonName(name) {
                let content = m[1] ?? ""
                return hit(.task, .createDraft(recipient: name, content: content), content.isEmpty ? "Draft to \(name)" : "Draft to \(name): “\(content)”")
            }
        }
        if let m = tell.match(s), let name = m[0], isPersonName(name), let content = m[1] {
            return hit(.task, .createDraft(recipient: name, content: content), "Draft to \(name): “\(content)”")
        }
        return nil
    }

    // MARK: References resolved against context

    static let openPronoun = Rx(#"(?:open|switch to|go to|show|bring up|pull up|focus on|focus|activate)\s+"# + pronoun + #"(?:\s+app)?"#)
    /// Window references: "it", "that", "this", "that window" ("this window" is explicit: the active window).
    static let windowRef = #"(?:it|that|this|that window|that app)"#
    static let maximizePronoun = Rx(#"(?:(?:maximize|maximise|expand)\s+"# + windowRef + #"|make\s+"# + windowRef + #"\s+(?:full ?screen|full size|maximized))"#)
    static let movePronounSide = Rx(#"(?:move|put|snap|send|place|push)\s+"# + windowRef + #"\s+(?:to\s+|on\s+|onto\s+)?(?:the\s+)?"# + positionWords)
    static let centerPronoun = Rx(#"(?:center|centre)\s+"# + windowRef + #"|(?:move|put)\s+"# + windowRef + #"\s+(?:to\s+|in\s+)?(?:the\s+)?(?:center|centre|middle)"#)
    static let movePronounNowhere = Rx(#"(?:move|put|place|shift)\s+(?:it|that|this)(?:\s+window)?(?:\s+(?:over there|over|there|somewhere|around|elsewhere))?"#)
    static let resizePronoun = Rx(#"make\s+"# + windowRef + #"\s+"# + degree + sizes)
    static let draftPronoun = Rx(draftVerb + #"\s+"# + personPronoun + #"(?:"# + connector + #"(.+))?"#)
    static let draftPronounAsk = Rx(draftVerb + #"\s+"# + personPronoun + #"\s*,?\s+(?:and\s+|to\s+)?((?:ask|asking)\b.+)"#)
    static let replyThat = Rx(#"(?:reply|respond|answer)(?:\s+to)?\s+(?:that|this|the)\s+(?:email|message|mail|one)(?:"# + connector + #"(.+))?"#)
    /// "draft a reply saying …", "write a response", "reply to it saying …": the open message.
    /// Content needs an explicit connector so "reply to sarah that …" stays a named reply.
    static let explicitConnector = #"(?:\s*[,:]\s*|\s+(?:saying|that|to say|with)\s+)"#
    static let replyCurrent = Rx(#"(?:(?:draft|write|compose|send|prepare)\s+(?:a\s+|the\s+)?(?:reply|response|answer)|reply|respond)(?:\s+to\s+(?:it|that|this))?(?:"# + explicitConnector + #"(.+))?"#)
    static let reviewPronoun = Rx(#"(?:show|read|let me see|display)\s+(?:me\s+)?(?:it|that|this|the reply|my reply|the response)(?:\s+to me)?(?:\s+(?:before sending|first))?"#)
    static let sendTo = Rx(#"send\s+(?:it|this|that|the draft)\s+to\s+.+"#)
    static let searchPronoun = Rx(#"(?:find|show(?: me)?|open|search for|look for|pull up|read)\s+(her|his|their)\s+((?:(?:latest|last|newest|most recent|recent|new|unread)\s+)?(?:email|e-mail|mail|message)s?\b.*)"#)
    static let findPronoun = Rx(#"(?:find|search for|look for|show me|open)\s+(?:it|that|this|them)"#)
    static let changePronoun = Rx(#"(?:change|replace|make|turn)\s+(?:it|that|this)\s+(?:to|with|into)\s+(.+)"#)
    static let barePronounCommand = Rx(#"(?:reply|respond|answer|write back)"#)

    /// "reply to Sarah's email saying …", "reply to her message that …", "reply to that email: …".
    static let replyToEmail = Rx(#"(?:reply|respond|answer|write back)\s+to\s+(?:([a-z][a-z.-]*)(?:'s|s')|her|his|their|that|this|the|my)\s+(?:latest\s+|last\s+)?(?:email|e-mail|message|mail|note)(?:\s+about\s+.+?)?"# + explicitConnector + #"(.+)"#)
    /// "delete/discard/close that reply" while a draft is open.
    static let discardDraft = Rx(#"(?:delete|discard|remove|trash|throw away|get rid of|close|scrap)\s+(?:that|the|this|my|our)\s+(?:reply|draft|response|email|message)(?:\s+(?:that\s+)?(?:we|you|i)\s+(?:just\s+)?(?:drafted|wrote|made|created))?"#)
    /// "the reply we just drafted", "what does the draft say": the current draft.
    static let draftReference = Rx(#"(?:(?:the|that|this|my|our)\s+(?:reply|draft|response)(?:\s+(?:that|which)\s+(?:we|you|i)\s+(?:just\s+)?(?:drafted|wrote|made|created))?|what does (?:it|the draft|the reply|my reply) say|what(?:'s| is) in (?:it|the draft|the reply))"#)

    /// Asked to delete/discard/close the open draft: say plainly what state it is in. Runs
    /// before the generic "not supported" rule.
    static func draftDiscard(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
        guard ctx.draft != nil || ctx.hasDraft, discardDraft.match(s) != nil else { return nil }
        return RuleHit(intent: Intent(kind: .unsupported, action: nil,
                                      summary: "I can't delete or discard drafts. The reply is still open in Mail and hasn't been sent; you can close it there.",
                                      source: .deterministic), stage: .clarify)
    }

    /// Reply to a named person's email when that email is the verified open message.
    static func replyToNamedEmail(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
        guard let m = replyToEmail.match(s), let content = m[1] else { return nil }
        guard let open = ctx.selectedMessage else { return nil }  // the planner finds the email first
        if let name = m[0]?.lowercased() {
            let sender = (open.sender + " " + (open.senderAddress ?? "")).lowercased()
            guard sender.contains(name) else { return nil }
        }
        return replyToOpen(ctx, content: content)
    }

    static func references(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
        // Calendar follow-up: right after a calendar question, a bare time continues it.
        if ctx.calendarTopic, let time = calendarTimeOnly(s) {
            return RuleHit(intent: Make.intent(.direct, .queryCalendar(timeExpression: time), "Check calendar \(time)"), stage: .context)
        }
        if let hit = replyToNamedEmail(s, ctx) { return hit }
        if ctx.draft != nil || ctx.hasDraft {
            if draftReference.match(s) != nil {
                return RuleHit(intent: Make.intent(.direct, .requestReview, "Show the current draft"), stage: .context)
            }
        }
        if openPronoun.match(s) != nil {
            guard let app = ctx.activeApp else {
                return RuleHit(intent: Make.ask(Make.whichApp), stage: .clarify, pending: .app(then: .activate))
            }
            return RuleHit(intent: Make.intent(.direct, .activateApp(app), "Open \(app.rawValue)"), stage: .context)
        }
        let target: WindowTarget = ctx.activeApp.map(WindowTarget.app) ?? .active
        if maximizePronoun.match(s) != nil {
            return RuleHit(intent: Make.intent(.direct, .moveWindow(target, .maximize), "Maximize \(target.displayName)"), stage: .context)
        }
        if let m = movePronounSide.match(s), let side = m[0]?.lowercased() {
            let position: WindowPosition = side == "left" ? .leftHalf : .rightHalf
            return RuleHit(intent: Make.intent(.direct, .moveWindow(target, position), "Move \(target.displayName) to the \(side) half"), stage: .context)
        }
        if centerPronoun.match(s) != nil {
            return RuleHit(intent: Make.intent(.direct, .moveWindow(target, .center), "Center \(target.displayName)"), stage: .context)
        }
        if movePronounNowhere.match(s) != nil {
            return RuleHit(intent: Make.ask(Make.wherePosition), stage: .clarify, pending: .position(window: target))
        }
        if let m = resizePronoun.match(s), let change = m[0].flatMap(ResizeChange.parse) {
            // Low-risk geometry default (PRD D-013): the current window.
            return RuleHit(intent: Make.intent(.direct, .resizeWindow(target, change), "Make \(target.displayName) \(change.rawValue)"), stage: .context)
        }
        if let m = sendNamed.match(s), let name = m[0], let draft = ctx.draft {
            let who = draftRecipientWords(draft, ctx)
            let named = Words.tokens(name)
            if !named.isEmpty, named.allSatisfy(who.contains) {
                return RuleHit(intent: Make.intent(.direct, .requestSend, "Send the current draft (needs confirmation)"), stage: .context)
            }
            let to = draft.recipients.joined(separator: ", ")
            return RuleHit(intent: Make.decline("The open draft is to \(to), not \(name), so I won't send it. Say “review the draft” to check it."),
                           stage: .clarify)
        }
        if sendTo.match(s) != nil {
            return RuleHit(intent: Make.ask("I can't change who a draft goes to by voice yet. Say “review the draft” to check its recipients."), stage: .clarify)
        }
        if let m = draftPronounAsk.match(s) ?? draftPronoun.match(s) {
            return person(ctx, then: .draft(content: m[1] ?? ""), verb: "write to")
        }
        if let m = replyCurrent.match(s) {
            return replyToOpen(ctx, content: m[0] ?? "") ?? person(ctx, then: .draft(content: m[0] ?? ""), verb: "reply to")
        }
        if reviewPronoun.match(s) != nil {
            guard ctx.hasDraft || ctx.draft != nil else {
                return RuleHit(intent: Make.ask("There's no draft yet. Who should I write to?"), stage: .clarify)
            }
            return RuleHit(intent: Make.intent(.direct, .requestReview, "Review the current draft"), stage: .context)
        }
        if let m = replyThat.match(s) {
            return replyToOpen(ctx, content: m[0] ?? "") ?? person(ctx, then: .draft(content: m[0] ?? ""), verb: "reply to")
        }
        if barePronounCommand.match(s) != nil {
            return replyToOpen(ctx, content: "") ?? person(ctx, then: .draft(content: ""), verb: "reply to")
        }
        if let m = searchPronoun.match(s), let rest = m[1] {
            return person(ctx, then: .search(rest: rest), verb: "search for")
        }
        if findPronoun.match(s) != nil {
            guard let message = ctx.openMessage else { return RuleHit(intent: Make.ask("What should I look for?"), stage: .clarify) }
            return RuleHit(intent: Make.intent(.direct, .readMessage(query: message), "Find “\(message)”"), stage: .context)
        }
        if let m = changePronoun.match(s), let new = m[0] {
            guard let old = ctx.lastEditedText else {
                return RuleHit(intent: Make.ask("Which text should I change to “\(new)”?"), stage: .clarify, pending: .textToReplace(replacement: new))
            }
            return RuleHit(intent: Make.intent(.edit, .replaceText(old: old, new: new), "Replace “\(old)” with “\(new)”"), stage: .context)
        }
        return nil
    }

    /// Resolve a person reference: exactly one recent person, else ask.
    /// A reply to the message the executor verified as open: its sender is the recipient
    /// (never guessed from recent people). Without content, ask for it.
    static func replyToOpen(_ ctx: ConversationContext, content: String) -> RuleHit? {
        guard let message = ctx.selectedMessage else { return nil }
        let name = message.sender
        let text = content.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return RuleHit(intent: Make.ask("What should the reply to \(name) say?"), stage: .clarify,
                           pending: .draftContent(recipient: name))
        }
        return RuleHit(intent: Make.intent(.task, .createDraft(recipient: name, content: text), "Draft a reply to \(name): “\(text)”"),
                       stage: .context)
    }

    static let contentLead = Rx(#"(?:(?:just\s+)?(?:say|saying|write|tell (?:her|him|them))(?:\s+that)?|it should say(?:\s+that)?|that)\s+(.+)"#)
    static let dismiss = Rx(#"(?:never ?mind|forget it|no reply|don't reply|do not reply|nothing)"#)

    static func person(_ ctx: ConversationContext, then: PendingQuestion.PersonFollowUp, verb: String) -> RuleHit {
        switch ctx.recentPeople.count {
        case 1:
            return RuleHit(intent: completePerson(ctx.recentPeople[0], then), stage: .context)
        case 0:
            return RuleHit(intent: Make.ask("Who should I \(verb)?"), stage: .clarify, pending: .person(candidates: [], then: then))
        default:
            let names = ctx.recentPeople
            let list = names.dropLast().joined(separator: ", ") + " or " + names.last!
            return RuleHit(intent: Make.ask("Did you mean \(list)?"), stage: .clarify, pending: .person(candidates: names, then: then))
        }
    }

    static func completePerson(_ name: String, _ then: PendingQuestion.PersonFollowUp) -> Intent {
        switch then {
        case .draft(let content):
            return Make.intent(.task, .createDraft(recipient: name, content: content), "Draft to \(name)")
        case .search(let rest):
            let query = "\(rest) from \(name)"
            return Make.intent(.direct, .readMessage(query: query), "Find “\(query)”")
        }
    }

    // MARK: Draft editing (T-023B, ADR 0010)

    /// Edit commands FlowText understands ("add that …", "change 3:30 to 4", "remove the last
    /// sentence", "undo that change") become `edit_text` for the current draft, carrying the
    /// command with its wrappers removed and its own punctuation kept. Deterministic only.
    /// Without a draft, edits that need one get a question; replace/insert keep their
    /// existing routing (they also apply to other text).
    /// "What does the draft say?" reads the draft back; it is never an edit.
    static func draftReview(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
        guard ctx.draft != nil || ctx.hasDraft, draftReference.match(s) != nil else { return nil }
        return RuleHit(intent: Make.intent(.direct, .requestReview, "Show the current draft"), stage: .context)
    }

    static func draftEdit(raw: String, cleaned s: String, _ ctx: ConversationContext) -> RuleHit? {
        guard case .edit(let op) = EditCommandParser.parse(s) else { return nil }
        switch op {
        case .insert: return nil  // "type …" stays insert_text (dictation into the focused field)
        case .append, .prepend:
            // "Add Sarah to the meeting" is not draft text: only unmistakable phrasings append.
            guard draftAppend.match(s) != nil else { return nil }
        case .replace, .delete, .undo, .rewrite: break
        }
        guard ctx.draft != nil || ctx.hasDraft else {
            switch op {
            case .replace, .rewrite: return nil  // may be about other text; existing routing applies
            default: return RuleHit(intent: Make.ask("There's no draft open to edit. Which message should I reply to?"), stage: .clarify)
            }
        }
        let payload = s + Cleaner.terminalPunctuation(raw)
        return RuleHit(intent: Make.intent(.edit, .editText(payload), "Edit the draft: “\(payload)”"), stage: .context)
    }

    private static let draftAppend = Rx(
        #"(?:and\s+)?(?:also\s+)?(?:add|say|mention|write|include|tell (?:her|him|them))\s+that\s+.+|also\s+(?:say|add|mention|write)\s+.+|(?:start|begin|open) (?:it |the (?:draft|reply|email|message) )?with\s+.+"#)

    // MARK: Follow-up answers

    static func answer(_ s: String, to pending: PendingQuestion) -> Intent? {
        // A quick app/window command ("switch to Mail", "minimize this window") is never an
        // answer: it runs, and the question stays open (ADR 0011).
        // ("Which app?" is the exception: "open Notes" answers it.)
        if case .app = pending {} else if isQuickAppCommand(s) { return nil }
        let lower = s.lowercased()
        switch pending {
        case .app(let then):
            guard let app = KnownApp.fromPhrase(lower) ?? (activate.match(s).flatMap { $0[0] }.flatMap(KnownApp.fromPhrase)) else { return nil }
            switch then {
            case .activate: return Make.intent(.direct, .activateApp(app), "Open \(app.rawValue)")
            case .move(let p): return Make.intent(.direct, .moveWindow(.app(app), p), "Move \(app.rawValue)")
            case .resize(let c): return Make.intent(.direct, .resizeWindow(.app(app), c), "Resize \(app.rawValue)")
            }
        case .person(let candidates, let then):
            let ordinals = ["first": 0, "the first one": 0, "one": 0, "1": 0, "second": 1, "the second one": 1, "two": 1, "2": 1,
                            "third": 2, "the third one": 2, "three": 2, "3": 2]
            if let i = ordinals[lower], i < candidates.count { return completePerson(candidates[i], then) }
            if let match = candidates.first(where: { lower.contains($0.lowercased()) }) { return completePerson(match, then) }
            if candidates.isEmpty, let m = Rx(#"(?:to\s+)?([a-z][a-z'.-]*)"#).match(s), let name = m[0], isPersonName(name) {
                return completePerson(name, then)
            }
            return nil
        case .position(let window):
            let p: WindowPosition?
            if lower.contains("left") { p = .leftHalf }
            else if lower.contains("right") { p = .rightHalf }
            else if lower.contains("center") || lower.contains("centre") || lower.contains("middle") { p = .center }
            else if lower.contains("max") || lower.contains("full") { p = .maximize }
            else { p = nil }
            return p.map { Make.intent(.direct, .moveWindow(window, $0), "Move \(window.displayName)") }
        case .confirm(let proposed, let otherwise, let kind):
            let w = Words.tokens(s)
            if !Set(w).isDisjoint(with: ["yes", "yeah", "yep", "correct", "right", "sure", "ok", "okay"]) {
                return Make.intent(kind, proposed, "Confirmed")
            }
            if !Set(w).isDisjoint(with: ["no", "nope", "keep"]) { return Make.intent(kind, otherwise, "Kept as heard") }
            return nil
        case .calendarTime:
            return calendarTimeOnly(s).map { hit(.direct, .queryCalendar(timeExpression: $0), "Check calendar \($0)").intent }
        case .plan:
            return nil  // answered by the plan runner
        case .draftContent(let recipient):
            if dismiss.match(s) != nil {
                return Intent(kind: .unsupported, action: nil, summary: "Okay, I won't write a reply.", source: .deterministic)
            }
            let content = (contentLead.match(s).flatMap { $0[0] } ?? s).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty, !Words.contentTokens(content).isEmpty else { return nil }
            return Make.intent(.task, .createDraft(recipient: recipient, content: content), "Draft a reply to \(recipient): “\(content)”")
        case .textEdit(_, let options):
            guard TextEditingSession.isAnswer(s, optionCount: options.count) else { return nil }
            return Make.intent(.edit, .editText(s), "Answer the draft question: “\(s)”")
        case .textToReplace(let replacement):
            guard !lower.isEmpty, !Words.contentTokens(s).isEmpty else { return nil }
            return Make.intent(.edit, .replaceText(old: s, new: replacement), "Replace “\(s)” with “\(replacement)”")
        }
    }

    // MARK: Helpers

    /// Words identifying a draft's recipients: address local parts, plus the replied-to sender's name.
    static func draftRecipientWords(_ draft: DraftSnapshot, _ ctx: ConversationContext) -> Set<String> {
        var words = Set(draft.recipients.flatMap { Words.tokens(String($0.split(separator: "@").first ?? "")) })
        if let m = ctx.selectedMessage, draft.inReplyTo == m.id { words.formUnion(Words.tokens(m.sender)) }
        return words
    }

    private static let timeLead = Rx(#"(?:(?:and|but|what|how)\s+)?(?:about\s+)?(?:for\s+)?(.+?)\??"#)
    private static let timeConnectors: Set<String> = [
        "at", "on", "in", "the", "this", "next", "around", "about", "by", "from", "to", "between", "of", "and", "o", "clock",
        "oclock", "am", "pm", "day", "after", "later", "early", "late",
    ]

    /// The utterance is only a time ("today", "at four", "what about Friday afternoon?"): returns
    /// it without the lead-in, else nil. At least one real time word is required.
    static func calendarTimeOnly(_ s: String) -> String? {
        let time = (timeLead.match(s).flatMap { $0[0] } ?? s).trimmingCharacters(in: .whitespaces)
        let tokens = Words.tokens(time)
        guard !tokens.isEmpty, tokens.count <= 8, tokens.contains(where: Guard.isTimeWord),
              tokens.allSatisfy({ Guard.isTimeWord($0) || timeConnectors.contains($0) })
        else { return nil }
        return time
    }

    static func hit(_ kind: IntentKind, _ action: FlowAction, _ summary: String) -> RuleHit {
        RuleHit(intent: Make.intent(kind, action, summary), stage: .fastPath)
    }

    /// Drops a leading "the"/"my"/"a" from a captured query.
    static func strip(_ q: String) -> String {
        var s = q.trimmingCharacters(in: .whitespaces)
        for prefix in ["the ", "my ", "a ", "an "] where s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        return s
    }
}
