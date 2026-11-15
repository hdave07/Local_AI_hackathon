import FlowCore
import FlowLLM
import FlowRouting
import Foundation

/// Result of turning one utterance into work.
public enum PlanningOutcome: Sendable {
    /// A bounded plan ready to run.
    case plan(Plan)
    /// stop / cancel / stop dictation: handled by the runner, never planned.
    case control(Intent)
    /// Information is missing before anything can be planned. `pending` lets the next
    /// utterance answer it (FlowRouting follow-up).
    case clarification(Intent, pending: PendingQuestion?)
    /// Not supported (e.g. close, delete); nothing is executed.
    case declined(Intent)
    case failure(ClassificationError)
}

/// Deterministic planner: utterance → clauses → validated intents (FlowRouting) → steps.
///
/// The planner is capability-based: it knows "find a message", "compose", "review",
/// "send", "look up", "arrange windows", "interact" — not Mail, Messages or WhatsApp.
/// Channel specifics come from `ChannelCatalog`. No model plans anything: Bonsai may
/// interpret one clause through the router's fallback, but step order, dependencies,
/// implied steps, risk and confirmation are code.
public struct TaskPlanner: Sendable {
    public let router: IntentRouterCore
    public let channels: ChannelResolver

    public init(router: IntentRouterCore, catalog: ChannelCatalog = .standard) {
        self.router = router
        self.channels = ChannelResolver(catalog: catalog)
    }

    public func plan(_ utterance: String, context: ConversationContext) async -> PlanningOutcome {
        // Channel names ("email", "text", "whatsapp", or any catalog channel) also start clauses.
        let channelVerbs = Set(channels.catalog.channels.flatMap(\.spokenNames).filter { !$0.contains(" ") })
        // Answering "What should the reply say?": the whole utterance is dictated content, never
        // split into commands, and the draft stays a reply to the open message.
        var answeringReply = false
        if case .draftContent = context.pending { answeringReply = true }
        // "…, and show it to me" at the end asks for a review; it is not part of the content.
        let (spoken, wantsReview) = Self.splitTrailingReview(utterance)
        let body = answeringReply ? spoken : Self.expandReplyToEmail(spoken, context: context)
        // Filler-only clauses ("Um, open notes" splits into "Um" + "open notes") carry no command.
        var clauses = answeringReply ? [body] : Self.clauses(body, extraVerbs: channelVerbs).filter { !Self.isFillerOnly($0) }
        // Requests that only make sense whole ("open Mail and Calendar and put them side by side") are not split.
        if clauses.count > 1, IntentRouterCore.isWholeUtteranceCommand(body) { clauses = [body] }
        // A discourse opener split off by its comma ("Actually, change 3:30 to 4") is not a command.
        while clauses.count > 1, Self.isOpenerOnly(clauses[0]) { clauses.removeFirst() }
        if wantsReview { clauses.append("show it to me") }
        guard !clauses.isEmpty else { return .failure(.emptyInput) }

        var builder = Builder(context: context, catalog: channels.catalog)
        for raw in clauses {
            let resolved = channels.resolve(raw)
            let decision = await router.route(resolved.clause, context: builder.simulated)
            let intent: Intent
            switch decision.outcome {
            case .failure(let error): return .failure(error)
            case .success(let i): intent = i
            }
            switch intent.kind {
            case .control:
                return .control(intent)
            case .clarification:
                return .clarification(intent, pending: clauses.count == 1 ? decision.pending : nil)
            case .unsupported:
                return .declined(intent)
            default:
                guard var action = intent.action else { return .declined(intent) }
                // Clauses lose the utterance's final "." / "!" / "?"; text added to a draft keeps it.
                if case .editText(let command) = action, raw == clauses.last, let mark = Self.terminalMark(utterance),
                   !command.hasSuffix(mark) {
                    action = .editText(command + mark)
                }
                builder.add(action, clause: raw, spokenChannel: resolved.channel, summary: intent.summary,
                            forceReply: answeringReply && Capability(action) == .compose)
            }
            if builder.steps.count > Plan.maxSteps {
                return .clarification(
                    Intent(kind: .clarification, summary: "That's more than \(Plan.maxSteps) steps. Please say it in smaller parts.",
                           source: .deterministic), pending: nil)
            }
        }
        return .plan(Plan(utterance: utterance, steps: builder.steps))
    }

    // MARK: - Clauses

    static let trailingReview = try! NSRegularExpression(
        pattern: #"\s*[,;]?\s+(?:and\s+)?(?:then\s+)?(?:show|let me see|read back|display)\s+(?:me\s+)?(?:it|that|the draft|the reply|my reply)(?:\s+to me)?(?:\s+first)?\s*[.!?]?\s*$"#,
        options: .caseInsensitive)

    /// Splits a trailing review request ("…, and show it to me") off the utterance.
    static func splitTrailingReview(_ utterance: String) -> (String, Bool) {
        let ns = utterance as NSString
        guard let m = trailingReview.firstMatch(in: utterance, range: NSRange(location: 0, length: ns.length)), m.range.location > 0
        else { return (utterance, false) }
        return (ns.substring(to: m.range.location), true)
    }

    static let replyToNamedEmail = try! NSRegularExpression(
        pattern: #"^(?:.*?\b)?(?:reply|respond|answer|write back)\s+to\s+([A-Za-z][A-Za-z.-]*)(?:'s|’s|s')\s+((?:latest\s+|last\s+)?(?:email|e-mail|message|mail|note)(?:\s+about\s+.+?)?)(?:\s*[,:]\s*|\s+(?:saying|that|to say|with)\s+)(.+)$"#,
        options: .caseInsensitive)

    /// "reply to Sarah's email saying X" when Sarah's email is not the open message becomes
    /// "find Sarah's email, reply saying X": find (and ask which, if several), then reply.
    static func expandReplyToEmail(_ utterance: String, context: ConversationContext) -> String {
        let ns = utterance as NSString
        guard let m = replyToNamedEmail.firstMatch(in: utterance, range: NSRange(location: 0, length: ns.length)) else { return utterance }
        let name = ns.substring(with: m.range(at: 1))
        if let open = context.selectedMessage,
           (open.sender + " " + (open.senderAddress ?? "")).lowercased().contains(name.lowercased()) {
            return utterance  // already open: the router replies to it directly
        }
        let what = ns.substring(with: m.range(at: 2))
        let content = ns.substring(with: m.range(at: 3))
        return "find \(name)'s \(what), reply saying \(content)"
    }

    /// The same disfluencies FlowRouting's cleaner removes (uh, um, erm, uhm).
    static let fillers: Set<String> = ["uh", "um", "erm", "uhm"]

    static func terminalMark(_ utterance: String) -> String? {
        let t = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last, ".!?".contains(last), !t.hasSuffix("..") else { return nil }
        return String(last)
    }
    static let openers: Set<String> = ["actually", "sorry", "wait", "oh", "ok", "okay", "so", "well", "hmm", "yeah", "also"]

    static func isOpenerOnly(_ clause: String) -> Bool {
        let words = clause.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy { openers.contains($0) || fillers.contains($0) }
    }

    /// A clause made only of filler words, e.g. "Um" before a comma in recognizer output.
    static func isFillerOnly(_ clause: String) -> Bool {
        let words = clause.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy { fillers.contains($0) }
    }

    /// Words that start a new command clause.
    static let commandVerbs: Set<String> = [
        "open", "launch", "start", "switch", "go", "bring", "show", "display", "find", "search", "look", "check", "read",
        "draft", "reply", "respond", "write", "message", "compose", "send", "tell", "put",
        "move", "snap", "maximize", "center", "make", "tile", "scroll", "click", "press", "tap", "focus", "type",
        "replace", "change", "review", "let", "am", "do", "what",
    ]

    /// Words that make a clause carry dictated content, inside which a plain "and" is text.
    static let contentMarkers = #"\b(?:saying|that|tell|type|asking|ask|say|to say)\b|:"#

    static let boundary = try! NSRegularExpression(
        pattern: #"\s*(?:,\s*(?:and\s+)?(?:then\s+)?|;\s*|\s+and then\s+|\s+then\s+|\s+and\s+)"#, options: [.caseInsensitive])

    /// Splits "find X, draft Y, and show it" into clauses. A boundary is used only when the
    /// next words start a command; a plain " and " never splits dictated content.
    public static func clauses(_ utterance: String, extraVerbs: Set<String> = []) -> [String] {
        let verbs = commandVerbs.union(extraVerbs)
        let text = utterance.trimmingCharacters(in: CharacterSet(charactersIn: ".!? ").union(.whitespacesAndNewlines))
        let ns = text as NSString
        var clauses: [String] = []
        var start = 0
        for match in boundary.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.range.location >= start else { continue }
            let left = ns.substring(with: NSRange(location: start, length: match.range.location - start))
            let rightStart = match.range.location + match.range.length
            let right = ns.substring(from: rightStart)
            let nextWord = right.split(separator: " ").first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
            let separator = ns.substring(with: match.range).lowercased()
            let plainAnd = separator.trimmingCharacters(in: .whitespaces) == "and"
            guard verbs.contains(nextWord) else { continue }
            if plainAnd, left.range(of: contentMarkers, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if !left.trimmingCharacters(in: .whitespaces).isEmpty { clauses.append(left.trimmingCharacters(in: .whitespaces)) }
            start = rightStart
        }
        let tail = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { clauses.append(tail) }
        return clauses
    }

    // MARK: - Step building (capability-based)

    struct Builder {
        var simulated: ConversationContext
        let real: ConversationContext
        let catalog: ChannelCatalog
        var steps: [PlanStep] = []
        /// Last step that finds a message / writes a draft / reviews it, with its channel.
        var messageStep: (id: Int, channel: MessageChannel)?
        var draftStep: (id: Int, channel: MessageChannel)?
        var reviewStep: Int?

        init(context: ConversationContext, catalog: ChannelCatalog) {
            simulated = context
            real = context
            self.catalog = catalog
        }

        mutating func append(
            _ action: FlowAction, dependsOn: [Int] = [], preconditions: [Precondition] = [], expectation: Expectation,
            origin: PlanStep.Origin = .spoken, replies: Bool = false, channel: MessageChannel? = nil, summary: String
        ) -> Int {
            let id = steps.count
            steps.append(PlanStep(
                id: id, action: action, dependsOn: dependsOn, preconditions: preconditions, expectation: expectation,
                origin: origin, repliesToSelectedMessage: replies, channel: channel, summary: summary))
            return id
        }

        /// Activate the channel's app first when it is allowlisted and not already active.
        /// Channels without an allowlisted app are prepared by their adapter instead.
        mutating func prepare(_ channel: MessageChannel) -> [Int] {
            guard let app = catalog.info(channel)?.app else { return [] }
            if let existing = steps.first(where: { $0.action == .activateApp(app) }) { return [existing.id] }
            if simulated.activeApp == app { return [] }
            let id = append(.activateApp(app), expectation: .appFrontmost(app), origin: .implied, summary: "Open \(app.rawValue)")
            simulated.activeApp = app
            return [id]
        }

        func name(_ channel: MessageChannel) -> String { catalog.info(channel)?.displayName ?? channel.rawValue }

        /// Channel for a messaging step: spoken > the message/draft it continues > default.
        func channel(spoken: MessageChannel?, continuing: MessageChannel?) -> MessageChannel {
            spoken ?? continuing ?? catalog.defaultChannel
        }

        mutating func add(_ action: FlowAction, clause: String, spokenChannel: MessageChannel?, summary: String,
                          forceReply: Bool = false) {
            switch Capability(action) {
            case .activate:
                if case .activateApp(let app) = action { _ = append(action, expectation: .appFrontmost(app), summary: summary) }
                if case .activateApp(let app) = action { simulated.activeApp = app }
            case .arrangeWindows:
                _ = append(action, expectation: .windowChanged, summary: summary)
            case .interact:
                _ = append(action, expectation: .uiActed, summary: summary)
            case .scroll:
                _ = append(action, expectation: .scrolled, summary: summary)
            case .lookup:
                _ = append(action, expectation: .lookupAnswered, summary: summary)

            case .findMessage:
                guard case .readMessage(let query) = action else { return }
                let ch = channel(spoken: spokenChannel, continuing: nil)
                let id = append(action, dependsOn: prepare(ch), expectation: .messageOpened(matching: query), channel: ch,
                                summary: "Find “\(query)” in \(name(ch))")
                messageStep = (id, ch)
                // Until the executor verifies the message, refer to its sender uniquely by the
                // person named in the query (or generically).
                simulated.openMessage = query
                simulated.recentPeople = [ConversationContext.person(inQuery: query) ?? "the sender"]
                simulated.selectedMessage = nil

            case .compose:
                guard case .createDraft(let recipient, let content) = action else { return }
                let continuing = messageStep?.channel ?? real.selectedMessage?.channel
                if Self.isReply(clause) || forceReply, messageStep != nil || real.selectedMessage != nil {
                    // A reply stays in the channel of the message it answers.
                    let ch = spokenChannel ?? continuing ?? catalog.defaultChannel
                    let deps = messageStep.map { [$0.id] } ?? []
                    let id = append(
                        action, dependsOn: deps, preconditions: deps.isEmpty ? [.messageSelected] : [],
                        expectation: .draftWritten(recipient: nil, content: content), replies: true, channel: ch,
                        summary: content.isEmpty ? "Draft a reply" : "Draft a reply: “\(content)”")
                    draftStep = (id, ch)
                } else {
                    let ch = channel(spoken: spokenChannel, continuing: nil)
                    let id = append(
                        action, dependsOn: prepare(ch), expectation: .draftWritten(recipient: recipient, content: content),
                        channel: ch, summary: "Draft a \(name(ch)) message to \(recipient)" + (content.isEmpty ? "" : ": “\(content)”"))
                    draftStep = (id, ch)
                }
                reviewStep = nil
                simulated.hasDraft = true

            case .editText:
                if case .editText(let command) = action {
                    // A FlowText command against the selected (verified) draft. It never runs
                    // without one: the router only emits it when a draft is in context.
                    let ch = draftStep?.channel ?? real.draft?.channel ?? catalog.defaultChannel
                    let deps = draftStep.map { [$0.id] } ?? []
                    let id = append(action, dependsOn: deps, preconditions: deps.isEmpty ? [.draftExists] : [],
                                    expectation: .draftEdited, channel: ch, summary: "Edit the draft: “\(command)”")
                    draftStep = (id, ch)
                    reviewStep = nil
                    return
                }
                let text: String
                switch action {
                case .insertText(let t): text = t
                case .replaceText(_, let new): text = new
                default: return
                }
                if let draft = draftStep ?? real.draft.map({ (id: -1, channel: $0.channel) }) {
                    let deps = draft.id >= 0 ? [draft.id] : []
                    let id = append(
                        action, dependsOn: deps, preconditions: deps.isEmpty ? [.draftExists] : [],
                        expectation: .draftWritten(recipient: nil, content: text), channel: draft.channel, summary: summary)
                    draftStep = (id, draft.channel)
                    reviewStep = nil
                } else {
                    _ = append(action, expectation: .uiActed, summary: summary)  // text in the focused field
                }
                simulated.lastEditedText = text

            case .review:
                let ch = draftStep?.channel ?? real.draft?.channel ?? catalog.defaultChannel
                let deps = draftStep.map { [$0.id] } ?? []
                reviewStep = append(
                    action, dependsOn: deps, preconditions: deps.isEmpty ? [.draftExists] : [], expectation: .draftShown,
                    channel: ch, summary: "Show the draft for review")

            case .send:
                // Never send what the user has not seen in its current version (spec 02 §9). The
                // live draft is always re-read and shown right before the confirmation (T-023C):
                // an earlier review may predate an edit made in Mail or by FlowText.
                let ch = draftStep?.channel ?? real.draft?.channel ?? catalog.defaultChannel
                var deps: [Int] = []
                if let review = reviewStep {
                    deps = [review]
                } else {
                    let d = draftStep.map { [$0.id] } ?? []
                    let review = append(
                        .requestReview, dependsOn: d, preconditions: d.isEmpty ? [.draftExists] : [], expectation: .draftShown,
                        origin: .implied, channel: ch, summary: "Show the draft for review")
                    reviewStep = review
                    deps = [review]
                }
                _ = append(
                    action, dependsOn: deps, preconditions: [.draftExists, .draftReviewedCurrentVersion], expectation: .sent,
                    channel: ch, summary: "Send the draft (needs your confirmation)")
            }
        }

        static func isReply(_ clause: String) -> Bool {
            !Set(clause.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
                .isDisjoint(with: ["reply", "respond", "answer", "response"])
        }
    }
}
