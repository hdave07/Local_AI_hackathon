import FlowAX
import FlowCalendar
import FlowMailSend
import FlowCore
import FlowMail
import FlowPlanner
import FlowRouting
import FlowWindow
import Foundation

/// Executor settings that bound what real execution may touch.
public struct ExecutorConfiguration: Sendable, Equatable {
    public enum MailScope: Sendable, Equatable {
        /// Test mode: every search is forced into this one local mailbox, and message
        /// references outside it are refused. Real mailboxes are never searched or opened.
        case testMailbox(String)
        /// Mail's unified Inbox (normal use; not enabled in this milestone).
        case inbox
    }

    public var mailScope: MailScope

    public init(mailScope: MailScope = .testMailbox("FlowTest")) {
        self.mailScope = mailScope
    }
}

/// One executed request, for the HUD and evidence. Contains no message bodies.
public struct ExecutionLogEntry: Sendable, Equatable {
    public let planID: UUID
    public let stepID: Int
    public let attempt: Int
    public let action: String
    public let status: ExecutionStatus
    public let observation: String
    public let userMessage: String
    public let timestamp: Date
}

/// The real `PlanExecuting` adapter (ADR 0005): FlowWindow for apps and windows, FlowAX for
/// generic UI, FlowMail for finding and opening messages. Every target is revalidated by
/// the module that acts on it. Drafting, editing, review, sending and calendar lookups are
/// not enabled and return `unsupported` without acting.
public final class MacPlanExecutor: PlanExecuting {
    private let engine: ExecutorEngine

    /// - Parameter drafts: reply drafting (T-023A). `nil` keeps drafting unsupported.
    /// - Parameter calendar: read-only calendar lookups (T-024). `nil` keeps them unsupported.
    @MainActor
    public init(window: WindowController, navigator: UINavigator, mail: MailController, drafts: MailDraftController? = nil,
                calendar: CalendarController? = nil, sender: MailSender? = nil,
                configuration: ExecutorConfiguration = ExecutorConfiguration()) {
        engine = ExecutorEngine(window: window, navigator: navigator, mail: mail, drafts: drafts, calendar: calendar,
                                sender: sender, configuration: configuration)
    }

    public func execute(_ request: ExecutionRequest) async -> ExecutionResult {
        await engine.execute(request)
    }

    @MainActor public var log: [ExecutionLogEntry] { engine.log }
    @MainActor public var configuration: ExecutorConfiguration { engine.configuration }
    @MainActor public var calendarScope: CalendarScope? { engine.calendar?.scope }
    // Test hooks: reuse the same controllers in another executor configuration.
    @MainActor var engineWindow: WindowController { engine.window }
    @MainActor var engineNavigator: UINavigator { engine.navigator }
    @MainActor var engineMail: MailController { engine.mail }
    @MainActor var engineDrafts: MailDraftController? { engine.drafts }
    @MainActor public var sender: MailSender? { engine.sender }
}

@MainActor
final class ExecutorEngine {
    let window: WindowController
    let navigator: UINavigator
    let mail: MailController
    let drafts: MailDraftController?
    let calendar: CalendarController?
    /// Confirmed sending (T-023C). `nil` or `.disabled` keeps `request_send` unsupported.
    let sender: MailSender?
    let configuration: ExecutorConfiguration
    private(set) var log: [ExecutionLogEntry] = []
    /// Message candidates belong to one search; a newer search makes older choices stale.
    private(set) var searchEpoch = 0

    init(window: WindowController, navigator: UINavigator, mail: MailController, drafts: MailDraftController?,
         calendar: CalendarController? = nil, sender: MailSender? = nil, configuration: ExecutorConfiguration) {
        self.calendar = calendar
        self.sender = sender
        self.window = window
        self.navigator = navigator
        self.mail = mail
        self.drafts = drafts
        self.configuration = configuration
    }

    func execute(_ request: ExecutionRequest) async -> ExecutionResult {
        // Safe checkpoint before acting (ADR 0005: honor Task cancellation).
        if Task.isCancelled { return finish(request, .init(status: .cancelled, userMessage: "Cancelled before acting.")) }

        let result: ExecutionResult
        switch request.action {
        case .activateApp(let app):
            result = await activate(app)
        case .moveWindow, .resizeWindow, .tileWindows:
            result = await arrange(request.action)
        case .clickElement, .focus, .scroll:
            result = await navigate(request.action)
        case .readMessage(let query):
            result = await readMessage(query, request)
        case .queryCalendar(let expression):
            result = await checkCalendar(expression)
        case .showCalendar(let expression):
            result = await showCalendar(expression)
        case .createDraft(_, let content):
            result = await createReply(content, request)
        case .requestReview:
            result = await review(request)
        case .insertText, .replaceText:
            result = Self.unsupported("Editing drafts by voice isn't enabled yet. Nothing was changed.")
        case .requestSend:
            result = await send(request)  // ExecutorSend.swift
        }
        return finish(request, result)
    }

    // MARK: Apps and windows (FlowWindow)

    private func activate(_ app: KnownApp) async -> ExecutionResult {
        let r = await window.perform(.activate(app))
        switch r.status {
        case .completed, .partiallyCompleted:
            // FlowWindow verified the app is frontmost; partial only means it has no open window.
            let note = r.status == .partiallyCompleted ? " It has no open window." : ""
            return ExecutionResult(status: .completed, observation: .appActive(app), retrySafe: true,
                                   userMessage: "\(app.rawValue) is in front.\(note)")
        case .unverified:
            return ExecutionResult(status: .unverified, retrySafe: true, userMessage: r.userMessage)
        case .unsupported:
            return ExecutionResult(status: .unsupported, userMessage: r.userMessage)
        case .failed:
            return ExecutionResult(status: .failed, error: Self.code(r.error), retrySafe: r.retrySafe, userMessage: r.userMessage)
        }
    }

    private func arrange(_ action: FlowAction) async -> ExecutionResult {
        guard let command = WindowCommand(action) else { return Self.unsupported("That window action isn't supported.") }
        let r = await window.perform(command)
        switch r.status {
        case .completed:
            guard let w = r.observed.first else { return ExecutionResult(status: .unverified, userMessage: r.userMessage) }
            let selected = SelectedWindow(app: KnownApp.allCases.first { $0.bundleIdentifier == w.app.bundleID },
                                          title: w.title.isEmpty ? nil : w.title, windowID: w.id.description)
            return ExecutionResult(status: .completed, observation: .window(selected), userMessage: r.userMessage)
        case .partiallyCompleted:
            return ExecutionResult(status: .partiallyCompleted, userMessage: r.userMessage)
        case .unverified:
            return ExecutionResult(status: .unverified, userMessage: r.userMessage)
        case .unsupported:
            return ExecutionResult(status: .unsupported, userMessage: r.userMessage)
        case .failed:
            if case .ambiguousWindow = r.error {
                return ExecutionResult(status: .needsClarification, userMessage: r.userMessage)
            }
            return ExecutionResult(status: .failed, error: Self.code(r.error), retrySafe: r.retrySafe, userMessage: r.userMessage)
        }
    }

    // MARK: Generic UI (FlowAX)

    private func navigate(_ action: FlowAction) async -> ExecutionResult {
        guard let command = NavCommand(action) else { return Self.unsupported("That UI action isn't supported.") }
        let r = await navigator.perform(command)
        switch r.status {
        case .completed:
            if case .scroll = action { return ExecutionResult(status: .completed, observation: .scrolled, userMessage: r.userMessage) }
            return ExecutionResult(status: .completed, observation: .uiActed(label: r.target?.label ?? ""), userMessage: r.userMessage)
        case .needsClarification:
            // The numbered overlay is shown; the planner has no generic choice observation yet (ADR 0005 §4).
            return ExecutionResult(status: .needsClarification, userMessage: r.userMessage)
        case .partiallyCompleted:
            return ExecutionResult(status: .partiallyCompleted, userMessage: r.userMessage)
        case .unverified:
            return ExecutionResult(status: .unverified, userMessage: r.userMessage)
        case .unsupported:
            return ExecutionResult(status: .unsupported, userMessage: r.userMessage)
        case .failed:
            let code: ExecutionErrorCode
            switch r.error {
            case .targetGone, .targetChanged, .staleNumbers: code = .staleTarget
            case .notFound, .noActiveNumbers, .numberOutOfRange: code = .targetNotFound
            case .accessibilityNotTrusted: code = .permissionDenied
            case .appNotFound, .noWindow, .noFrontmostApp: code = .appUnavailable
            default: code = .unknown
            }
            return ExecutionResult(status: .failed, error: code, retrySafe: r.retrySafe, userMessage: r.userMessage)
        }
    }

    // MARK: Messages (FlowMail, read-only)

    private func readMessage(_ spoken: String, _ request: ExecutionRequest) async -> ExecutionResult {
        guard (request.channel ?? .mail) == .mail else {
            return Self.unsupported("Only Mail is connected so far; \(request.channel!.rawValue) isn't.")
        }

        // Open exactly the message the user chose.
        if let pick = request.bindings.message {
            guard pick.channel == .mail, let ref = MailRefCodec.decode(pick.id) else {
                return ExecutionResult(status: .failed, error: .staleTarget, retrySafe: true, userMessage: "I lost track of that message.")
            }
            guard pick.epoch == searchEpoch else {
                return ExecutionResult(status: .failed, error: .staleTarget, retrySafe: true,
                                       userMessage: "The message list changed since you chose.")
            }
            guard scopeAllows(ref) else { return outOfScope() }
            return opened(await mail.perform(.openMessage(ref)))
        }

        let query: MailQuery
        switch MailQueryInterpreter.query(from: spoken, scope: configuration.mailScope) {
        case .query(let q): query = q
        case .refused(let refusal): return refusal
        }

        let found = await mail.perform(.find(query))
        switch found.status {
        case .needsClarification:
            searchEpoch += 1
            let refs = found.messages.map { Self.messageRef($0, epoch: searchEpoch) }
            return ExecutionResult(status: .needsClarification, observation: .messageCandidates(refs), retrySafe: true,
                                   userMessage: found.userMessage)
        case .completed where found.messages.count == 1:
            searchEpoch += 1
            // Opens the single match with full revalidation (same Message-ID, subject and sender).
            return opened(await mail.perform(.choose(1)))
        case .completed:
            // No matches: a clear answer, not worth retrying.
            return ExecutionResult(status: .failed, error: .targetNotFound, retrySafe: false, userMessage: found.userMessage)
        default:
            return Self.mailFailure(found)
        }
    }

    // MARK: Calendar (FlowCalendar, read-only)

    private func checkCalendar(_ expression: String) async -> ExecutionResult {
        guard let calendar else { return Self.unsupported("Checking the calendar isn't enabled.") }
        let r = await calendar.check(expression)
        guard let report = r.report else { return Self.calendarFailure(r) }
        let answer = AvailabilityAnswer(
            status: AvailabilityAnswer.Status(rawValue: report.status.rawValue) ?? .unknown,
            start: report.query.interval.start, end: report.query.interval.end,
            events: report.findings.map {
                AvailabilityAnswer.Event(title: $0.event.title, start: $0.event.start, end: $0.event.end, isAllDay: $0.event.isAllDay,
                                         effect: $0.effect.rawValue, calendar: $0.event.calendarTitle)
            },
            calendarsChecked: report.calendarsChecked, answer: report.answer)
        // The observation carries the answer to the user; the executor log keeps only the privacy-safe summary.
        return ExecutionResult(status: .completed, observation: .availability(answer), retrySafe: true,
                               userMessage: "calendar \(report.logSummary)")
    }

    private func showCalendar(_ expression: String) async -> ExecutionResult {
        guard let calendar else { return Self.unsupported("Showing the calendar isn't enabled.") }
        let r = await calendar.show(expression)
        guard let day = r.shownDay else { return Self.calendarFailure(r) }
        let label = "Calendar: " + TimeExpressionParser.describeDay(day, label: nil, calendar: .current)
        return r.verified
            ? ExecutionResult(status: .completed, observation: .uiActed(label: label), retrySafe: true, userMessage: r.userMessage)
            : ExecutionResult(status: .unverified, retrySafe: true, userMessage: r.userMessage)
    }

    static func calendarFailure(_ r: CalendarResult) -> ExecutionResult {
        switch r.error {
        case .noAccess: ExecutionResult(status: .failed, error: .permissionDenied, userMessage: r.userMessage)
        case .automationDenied: ExecutionResult(status: .failed, error: .permissionDenied, userMessage: r.userMessage)
        case .calendarNotFound: ExecutionResult(status: .failed, error: .appUnavailable, userMessage: r.userMessage)
        case .unrecognizedTime: ExecutionResult(status: .failed, error: .targetNotFound, userMessage: r.userMessage)
        default: ExecutionResult(status: .failed, error: .unknown, retrySafe: true, userMessage: r.userMessage)
        }
    }

    // MARK: Reply drafts (FlowMail, never sent)

    private func createReply(_ content: String, _ request: ExecutionRequest) async -> ExecutionResult {
        guard let drafts else { return Self.unsupported("Writing replies isn't enabled. Nothing was changed.") }
        guard (request.channel ?? .mail) == .mail else {
            return Self.unsupported("Only Mail replies are supported; \(request.channel!.rawValue) isn't connected.")
        }
        guard let pick = request.bindings.message else {
            return Self.unsupported("I can only write replies to an email you've opened. Find the email first.")
        }
        guard pick.channel == .mail, let ref = MailRefCodec.decode(pick.id) else {
            return ExecutionResult(status: .failed, error: .staleTarget, userMessage: "I lost track of that email; find it again.")
        }
        guard scopeAllows(ref) else { return outOfScope() }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "What should the reply say?")
        }
        // At most one draft per plan step, whatever the outcome of an earlier attempt.
        let key = "\(request.planID.uuidString)#\(request.stepID)"
        let r = await drafts.createReply(to: ref, content: text, key: key)
        return draftResult(r, inReplyTo: pick.id, presented: false)
    }

    private func review(_ request: ExecutionRequest) async -> ExecutionResult {
        guard let drafts else { return Self.unsupported("Reviewing drafts isn't enabled.") }
        guard let bound = request.bindings.draft else {
            return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "There's no draft to show.")
        }
        guard bound.channel == .mail, drafts.state(bound.id) != nil else {
            return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "I don't have that draft open.")
        }
        let r = await drafts.refresh(bound.id, present: true)
        return draftResult(r, inReplyTo: bound.inReplyTo, presented: true)
    }

    private func draftResult(_ r: MailDraftResult, inReplyTo: String?, presented: Bool) -> ExecutionResult {
        let snapshot = r.draft.map {
            DraftSnapshot(channel: .mail, id: $0.id, recipients: $0.recipients, subject: $0.subject, body: $0.body,
                          version: $0.version, inReplyTo: inReplyTo)
        }
        switch r.status {
        case .completed:
            guard let snapshot else { return ExecutionResult(status: .unverified, userMessage: r.userMessage) }
            return ExecutionResult(status: .completed, observation: presented ? .reviewShown(snapshot) : .draft(snapshot),
                                   userMessage: r.userMessage)
        case .unverified:
            // The draft may exist; never retried automatically (content step), never duplicated (step key).
            return ExecutionResult(status: .unverified, userMessage: r.userMessage)
        default:
            let code: ExecutionErrorCode
            switch r.error {
            case .recipientMismatch: code = .recipientMismatch
            case .draftAlreadyOpen, .draftAmbiguous: code = .draftAlreadyOpen
            case .messageGone, .referenceChanged: code = .staleTarget
            case .draftGone, .unknownDraft: code = .targetNotFound
            case .automationDenied, .automationNotDetermined: code = .permissionDenied
            case .timedOut: code = .timeout
            default: code = .unknown
            }
            return ExecutionResult(status: r.status == .unsupported ? .unsupported : .failed, error: code, userMessage: r.userMessage)
        }
    }

    private func opened(_ r: MailResult) -> ExecutionResult {
        switch r.status {
        case .completed:
            guard let m = r.opened else { return ExecutionResult(status: .unverified, userMessage: r.userMessage) }
            return ExecutionResult(status: .completed, observation: .messageOpened(Self.messageRef(m, epoch: searchEpoch)),
                                   retrySafe: true, userMessage: r.userMessage)
        case .unverified:
            return ExecutionResult(status: .unverified, userMessage: r.userMessage)
        default:
            return Self.mailFailure(r)
        }
    }

    static func mailFailure(_ r: MailResult) -> ExecutionResult {
        switch r.error {
        case .messageGone, .referenceChanged:
            return ExecutionResult(status: .failed, error: .staleTarget, retrySafe: true, userMessage: r.userMessage)
        case .automationDenied, .automationNotDetermined:
            return ExecutionResult(status: .failed, error: .permissionDenied, userMessage: r.userMessage)
        case .notInstalled, .noAccounts, .launchFailed:
            return ExecutionResult(status: r.status == .unsupported ? .unsupported : .failed, error: .appUnavailable,
                                   userMessage: r.userMessage)
        case .timedOut:
            return ExecutionResult(status: .failed, error: .timeout, retrySafe: true, userMessage: r.userMessage)
        case .mailboxNotFound, .noActiveCandidates, .numberOutOfRange, .invalidQuery:
            return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: r.userMessage)
        default:
            return ExecutionResult(status: r.status == .unsupported ? .unsupported : .failed, error: .unknown,
                                   retrySafe: r.retrySafe, userMessage: r.userMessage)
        }
    }

    private func scopeAllows(_ ref: MailMessageRef) -> Bool {
        switch configuration.mailScope {
        case .inbox: return true
        case .testMailbox(let name):
            return ref.mailbox.account == nil
                && ref.mailbox.path.split(separator: "/").last.map(String.init)?.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func outOfScope() -> ExecutionResult {
        Self.unsupported("Test mode only opens messages in the \(MailQueryInterpreter.mailboxName(configuration.mailScope) ?? "test") mailbox.")
    }

    static func messageRef(_ m: MailMessageSummary, epoch: Int) -> MessageRef {
        MessageRef(channel: .mail, id: MailRefCodec.encode(m.ref), sender: m.senderName.isEmpty ? m.senderAddress : m.senderName,
                   senderAddress: m.senderAddress.isEmpty ? nil : m.senderAddress, subject: m.subject,
                   date: m.dateReceived.map { Self.dateFormatter.string(from: $0) }, epoch: epoch)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    // MARK: Helpers

    nonisolated static func unsupported(_ message: String) -> ExecutionResult {
        ExecutionResult(status: .unsupported, userMessage: message)
    }

    static func code(_ error: WindowError?) -> ExecutionErrorCode {
        switch error {
        case .accessibilityNotTrusted: .permissionDenied
        case .appNotInstalled, .appNotRunning, .launchFailed, .noFrontmostApp, .noWindow: .appUnavailable
        case .windowGone, .changedSinceAction: .staleTarget
        default: .unknown
        }
    }

    private func finish(_ request: ExecutionRequest, _ result: ExecutionResult) -> ExecutionResult {
        log.append(ExecutionLogEntry(
            planID: request.planID, stepID: request.stepID, attempt: request.attempt, action: request.action.type.rawValue,
            status: result.status, observation: Self.describe(result.observation), userMessage: result.userMessage,
            timestamp: Date()))
        if log.count > 200 { log.removeFirst() }
        return result
    }

    static func describe(_ o: Observation) -> String {
        switch o {
        case .none: "none"
        case .appActive(let app): "app active: \(app.rawValue)"
        case .window(let w): "window: \(w.app?.rawValue ?? "?") \(w.title ?? "")"
        case .uiActed(let label): "acted on “\(label)”"
        case .scrolled: "scrolled"
        case .messageCandidates(let c): "\(c.count) candidate messages"
        case .messageOpened(let m): "opened: \(m.spoken)"
        case .draft(let d): "draft \(d.id.suffix(8)) v\(d.version) to \(d.recipients.joined(separator: ", "))"
        case .reviewShown(let d): "review shown: draft \(d.id.suffix(8)) v\(d.version)"
        case .lookupResult: "lookup answered"
        case .availability(let a): "availability: \(a.status.rawValue), \(a.events.count) event(s), calendars \(a.calendarsChecked.count)"
        case .sent(_, let queued): queued ? "send accepted (in Outbox)" : "send accepted (in Sent)"
        case .sendRehearsed: "dry-run send recorded (nothing sent)"
        }
    }
}

/// Opaque, reversible encoding of a FlowMail reference in `MessageRef.id`.
enum MailRefCodec {
    static func encode(_ ref: MailMessageRef) -> String {
        // Sorted keys: the same reference must always produce the same id (the runner compares ids).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(ref)) ?? Data()
        return "mail:" + data.base64EncodedString()
    }

    static func decode(_ id: String) -> MailMessageRef? {
        guard id.hasPrefix("mail:"), let data = Data(base64Encoded: String(id.dropFirst(5))) else { return nil }
        return try? JSONDecoder().decode(MailMessageRef.self, from: data)
    }
}

/// Turns the planner's verbatim `read_message` query into structured FlowMail criteria and
/// applies the configured scope (ADR 0006 §1). Deterministic; no model.
enum MailQueryInterpreter {
    static let ignorable: Set<String> = ["latest", "last", "newest", "recent", "new", "unread", "most", "the", "my", "email",
                                         "emails", "mail", "message", "messages"]

    static func mailboxName(_ scope: ExecutorConfiguration.MailScope) -> String? {
        if case .testMailbox(let name) = scope { return name }
        return nil
    }

    enum Interpretation {
        case query(MailQuery)
        case refused(ExecutionResult)
    }

    static func query(from spoken: String, scope: ExecutorConfiguration.MailScope) -> Interpretation {
        var text = spoken.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Leading verbs, if the planner kept them.
        text = text.replacingOccurrences(of: #"^(?:find|search(?:\s+for)?|look\s+for|open|read|show(?:\s+me)?|get|check|pull\s+up)\s+"#,
                                         with: "", options: [.regularExpression, .caseInsensitive])
        // "in the FlowTest mailbox", "in mailbox FlowTest", "in my inbox"
        var namedMailbox: String?
        let patterns = [#"\s*\b(?:in|from)\s+(?:the\s+|my\s+)?mailbox\s+([\w./-]+)"#,
                        #"\s*\b(?:in|from)\s+(?:the\s+|my\s+)?([\w./-]+)\s+(?:mailbox|folder)\b"#,
                        #"\s*\b(?:in|from)\s+(?:the\s+|my\s+)?(inbox)\b"#]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let nameRange = Range(m.range(at: 1), in: text), let whole = Range(m.range, in: text)
            else { continue }
            namedMailbox = String(text[nameRange])
            text.removeSubrange(whole)
            break
        }

        var query: MailQuery
        do throws(MailParseError) {
            query = try MailCommandParser.criteria(from: text)
        } catch {
            return .refused(ExecutionResult(status: .failed, error: .targetNotFound,
                                            userMessage: "Say who the email is from or what it's about."))
        }
        query.terms = query.terms.filter { !ignorable.contains($0.lowercased()) }
        if query.isEmpty {
            return .refused(ExecutionResult(status: .failed, error: .targetNotFound,
                                            userMessage: "Say who the email is from or what it's about."))
        }

        switch scope {
        case .testMailbox(let name):
            if let named = namedMailbox, named.caseInsensitiveCompare(name) != .orderedSame {
                return .refused(ExecutorEngine.unsupported("Test mode only searches the \(name) mailbox, not “\(named)”."))
            }
            query.mailbox = name  // forced: real mailboxes are never searched in test mode
        case .inbox:
            query.mailbox = namedMailbox.flatMap { $0.lowercased() == "inbox" ? nil : $0 }
        }
        return .query(query)
    }
}
