import FlowAX
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

    @MainActor
    public init(window: WindowController, navigator: UINavigator, mail: MailController,
                configuration: ExecutorConfiguration = ExecutorConfiguration()) {
        engine = ExecutorEngine(window: window, navigator: navigator, mail: mail, configuration: configuration)
    }

    public func execute(_ request: ExecutionRequest) async -> ExecutionResult {
        await engine.execute(request)
    }

    @MainActor public var log: [ExecutionLogEntry] { engine.log }
    @MainActor public var configuration: ExecutorConfiguration { engine.configuration }
}

@MainActor
final class ExecutorEngine {
    let window: WindowController
    let navigator: UINavigator
    let mail: MailController
    let configuration: ExecutorConfiguration
    private(set) var log: [ExecutionLogEntry] = []
    /// Message candidates belong to one search; a newer search makes older choices stale.
    private(set) var searchEpoch = 0

    init(window: WindowController, navigator: UINavigator, mail: MailController, configuration: ExecutorConfiguration) {
        self.window = window
        self.navigator = navigator
        self.mail = mail
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
        case .queryCalendar:
            result = Self.unsupported("Checking the calendar isn't available yet.")
        case .createDraft, .insertText, .replaceText, .requestReview:
            result = Self.unsupported("Writing or editing messages isn't enabled yet. Nothing was changed.")
        case .requestSend:
            result = Self.unsupported("Sending is disabled in this version. Nothing was sent.")
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
        case .draft: "draft"
        case .reviewShown: "review shown"
        case .lookupResult: "lookup answered"
        case .sent: "sent"
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
