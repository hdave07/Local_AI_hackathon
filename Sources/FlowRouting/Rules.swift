import FlowCore
import Foundation

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

    static let whichApp = "Which app: Mail, Calendar, Notes, Finder or Safari?"
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
        guard showNumbers.match(s) != nil || hideNumbers.match(s) != nil || chooseNumber.match(s) != nil else { return nil }
        return RuleHit(
            intent: Make.decline("Numbered selection isn't connected to voice yet."), stage: .overlay)
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

    static let unsupportedVerbs = Rx(#"(close|quit|delete|remove|trash|erase|discard|shut|kill|uninstall)\b.*"#)

    static func unsupported(_ s: String) -> RuleHit? {
        guard let m = unsupportedVerbs.match(s), let verb = m[0]?.lowercased() else { return nil }
        let what = ["close", "quit", "shut", "kill"].contains(verb) ? "Closing or quitting" : "Deleting"
        return RuleHit(intent: Make.decline("\(what) isn't supported yet."), stage: .clarify)
    }

    // MARK: Fast path (explicit targets only)

    static let activate = Rx(#"(?:open|launch|start|switch to|go to|bring up|show(?: me)?|pull up|focus on|focus|activate)\s+(.+?)"#)
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
    static let send = Rx(#"send(?:\s+(?:it|this|that|the draft|the email|the message|the reply|my reply|my draft|my email|my message|the mail))?(?:\s+now)?"#)
    static let review = Rx(#"(?:review|show me|let me (?:see|review|check)|read(?: back)?(?: me)?|check)\s+(?:the|my|this)\s+(?:draft|reply|response|email draft|message draft)(?:\s+before sending)?"#)

    // Mail search: explicit mail noun, never a calendar phrase.
    static let searchMailFor = Rx(#"(?:search|look through|check)\s+(?:my\s+|the\s+)?(?:mail|email|e-mail|inbox|messages)\s+for\s+(.+)"#)
    static let searchMail = Rx(#"(?:find|search for|look for|look up|show(?: me)?|open|pull up|get|read|bring up|go to)\s+((?:(?:the|my|an?)\s+)?(?:(?:latest|last|newest|most recent|recent|new|unread|first)\s+)?(?:email|e-mail|mail|message|messages|emails)\b.*)"#)
    static let searchMailPossessive = Rx(#"(?:find|search for|look for|look up|show(?: me)?|open|pull up|get|read)\s+((?:the\s+)?([a-z][a-z.-]*)'s\s+(?:(?:latest|last|newest|most recent|recent|new|unread)\s+)?(?:email|e-mail|mail|message)s?\b.*)"#)

    // Calendar queries.
    static let calendar = Rx(#"(?:do i have (?:anything|something|any meetings?|any events?|any plans|plans|a meeting|meetings)|am i (?:free|busy|available)|what(?:'s| is) on my (?:calendar|schedule)|what do i have(?: on)?|check my (?:calendar|schedule)|is there anything on my (?:calendar|schedule)|what(?:'s| is) my schedule)(?:\s+(.+))?"#)

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
        if let m = calendar.match(s) {
            guard let time = m[0]?.trimmingCharacters(in: .whitespaces), !time.isEmpty else {
                return RuleHit(intent: Make.ask("Which day or time should I check?"), stage: .clarify)
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
        return nil
    }

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

    static func references(_ s: String, _ ctx: ConversationContext) -> RuleHit? {
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
        if sendTo.match(s) != nil {
            return RuleHit(intent: Make.ask("I can't change who a draft goes to by voice yet. Say “review the draft” to check its recipients."), stage: .clarify)
        }
        if let m = draftPronounAsk.match(s) ?? draftPronoun.match(s) {
            return person(ctx, then: .draft(content: m[1] ?? ""), verb: "write to")
        }
        if let m = replyCurrent.match(s) {
            return person(ctx, then: .draft(content: m[0] ?? ""), verb: "reply to")
        }
        if reviewPronoun.match(s) != nil {
            guard ctx.hasDraft || ctx.draft != nil else {
                return RuleHit(intent: Make.ask("There's no draft yet. Who should I write to?"), stage: .clarify)
            }
            return RuleHit(intent: Make.intent(.direct, .requestReview, "Review the current draft"), stage: .context)
        }
        if let m = replyThat.match(s) {
            return person(ctx, then: .draft(content: m[0] ?? ""), verb: "reply to")
        }
        if barePronounCommand.match(s) != nil {
            return person(ctx, then: .draft(content: ""), verb: "reply to")
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

    // MARK: Follow-up answers

    static func answer(_ s: String, to pending: PendingQuestion) -> Intent? {
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
        case .plan:
            return nil  // answered by the plan runner
        case .textToReplace(let replacement):
            guard !lower.isEmpty, !Words.contentTokens(s).isEmpty else { return nil }
            return Make.intent(.edit, .replaceText(old: s, new: replacement), "Replace “\(s)” with “\(replacement)”")
        }
    }

    // MARK: Helpers

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
