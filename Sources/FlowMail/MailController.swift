import FlowAX
import Foundation

/// Typed Mail commands (read-only). Deterministic; no model involvement.
public enum MailCommand: Sendable, Equatable {
    case status(requestPermission: Bool)
    /// List matches. Several matches → numbered clarification (choosing opens).
    case find(MailQuery)
    case open(MailQuery)
    /// Open and read the body.
    case read(MailQuery)
    case choose(Int)
    /// Read the message Flow opened last, without reopening it.
    case readActive
    /// Planner entry points for previously found messages; always revalidated.
    case openMessage(MailMessageRef)
    case readMessage(MailMessageRef)

    public var name: String {
        switch self {
        case .status: "mail status"
        case .find: "find mail"
        case .open: "open mail"
        case .read: "read mail"
        case .choose(let n): "choose \(n)"
        case .readActive: "read current message"
        case .openMessage: "open message"
        case .readMessage: "read message"
        }
    }
}

public struct MailClarification: Sendable, Equatable {
    public let prompt: String
    public let options: [MailMessageSummary]  // option n is options[n - 1]
}

public struct MailResult: Sendable, Equatable {
    public let actionID: UUID
    public let command: MailCommand
    public let status: NavigationStatus
    public let messages: [MailMessageSummary]
    public let totalMatches: Int?
    public let clarification: MailClarification?
    public let opened: MailMessageSummary?
    public let observation: MailDisplayObservation?
    /// Present only for read commands. Never written to logs by Flow.
    public let content: MailMessageContent?
    public let error: MailError?
    public let evidence: [String]
    public let userMessage: String
    public let timestamp: Date

    public var retrySafe: Bool { error?.retrySafe ?? false }
}

/// Apple Mail read/search controller (spec 02 §9, plan T-022):
/// search → (clarify if several) → revalidate the reference → open in Mail → verify on
/// screen → read. Read-only: no sends, deletes, moves or flag writes.
@MainActor
public final class MailController {
    public struct Configuration: Sendable {
        public var candidatesLifetime: Duration = .seconds(300)
        public var maxBodyCharacters = 20_000
        public var verifyTimeout: Duration = .seconds(3)
        public var pollInterval: Duration = .milliseconds(150)
        public init() {}
    }

    enum Intent: Equatable { case open, read }

    struct Pending {
        let intent: Intent
        let candidates: [MailMessageSummary]
        let createdAt: ContinuousClock.Instant
    }

    public let backend: MailBackend
    public let configuration: Configuration
    private let verifier: MailDisplayVerifying?
    private var pending: Pending?
    /// The message Flow last opened (spec 02 §9 activeMessage).
    public private(set) var activeMessage: MailMessageSummary?

    public init(backend: MailBackend, verifier: MailDisplayVerifying? = nil, configuration: Configuration = Configuration()) {
        self.backend = backend
        self.verifier = verifier
        self.configuration = configuration
    }

    public var candidates: [MailMessageSummary] { pending?.candidates ?? [] }

    public func perform(_ command: MailCommand) async -> MailResult {
        do throws(MailError) {
            switch command {
            case .status(let request):
                return await status(command, request: request)
            case .find(let query):
                return try await search(query, intent: .open, command: command, act: false)
            case .open(let query):
                return try await search(query, intent: .open, command: command, act: true)
            case .read(let query):
                return try await search(query, intent: .read, command: command, act: true)
            case .choose(let number):
                try await ensureReady()
                guard let pending else { throw .noActiveCandidates }
                if ContinuousClock.now - pending.createdAt > configuration.candidatesLifetime {
                    self.pending = nil
                    throw .noActiveCandidates
                }
                guard (1...pending.candidates.count).contains(number) else {
                    throw .numberOutOfRange(number, count: pending.candidates.count)
                }
                let chosen = pending.candidates[number - 1]
                self.pending = nil
                return pending.intent == .read
                    ? try await readMessage(chosen.ref, expected: chosen, command: command)
                    : try await openMessage(chosen.ref, expected: chosen, command: command)
            case .readActive:
                try await ensureReady()
                guard let active = activeMessage else { throw .noActiveMessage }
                let fresh = try await revalidate(active.ref, expected: active)
                let content = try await readBody(fresh)
                return result(command, .completed, opened: fresh, content: content,
                              evidence: ["revalidated: same Message-ID, subject and sender", "read from Mail without reopening"],
                              message: "Read “\(fresh.subject)” from \(fresh.senderName.isEmpty ? fresh.senderAddress : fresh.senderName).")
            case .openMessage(let ref):
                try await ensureReady()
                return try await openMessage(ref, expected: nil, command: command)
            case .readMessage(let ref):
                try await ensureReady()
                return try await readMessage(ref, expected: nil, command: command)
            }
        } catch {
            return result(command, error.status, error: error, message: error.userMessage)
        }
    }

    // MARK: Status

    private func status(_ command: MailCommand, request: Bool) async -> MailResult {
        switch await backend.availability(requestPermission: request) {
        case .ready(let accounts):
            return result(command, .completed, evidence: ["accounts: \(accounts)", "Automation permission: granted"],
                          message: "Mail is ready (\(accounts) account\(accounts == 1 ? "" : "s")).")
        case .notInstalled: return result(command, .unsupported, error: .notInstalled, message: MailError.notInstalled.userMessage)
        case .noAccounts: return result(command, .unsupported, error: .noAccounts, message: MailError.noAccounts.userMessage)
        case .automationDenied: return result(command, .failed, error: .automationDenied, message: MailError.automationDenied.userMessage)
        case .automationNotDetermined:
            return result(command, .failed, error: .automationNotDetermined, message: MailError.automationNotDetermined.userMessage)
        case .notRunning:
            return result(command, .unverified, message: "Mail isn't running. Flow will start it in the background when you search.")
        }
    }

    private func ensureReady() async throws(MailError) {
        switch await backend.availability(requestPermission: true) {
        case .ready: return
        case .notInstalled: throw .notInstalled
        case .noAccounts: throw .noAccounts
        case .automationDenied: throw .automationDenied
        case .automationNotDetermined: throw .automationNotDetermined
        case .notRunning: throw .launchFailed
        }
    }

    // MARK: Search

    private func search(_ query: MailQuery, intent: Intent, command: MailCommand, act: Bool) async throws(MailError) -> MailResult {
        try Self.validate(query)
        try await ensureReady()
        let found = try await backend.search(query)
        let messages = found.messages
        let more = found.total > messages.count ? " Showing the newest \(messages.count) of \(found.total)." : ""

        switch messages.count {
        case 0:
            pending = nil
            return result(command, .completed, messages: [], total: 0,
                          evidence: ["searched \(query.description)"],
                          message: "No messages \(query.description).")
        case 1 where act:
            return intent == .read
                ? try await readMessage(messages[0].ref, expected: messages[0], command: command)
                : try await openMessage(messages[0].ref, expected: messages[0], command: command)
        case 1:
            pending = Pending(intent: intent, candidates: messages, createdAt: .now)
            return result(command, .completed, messages: messages, total: found.total,
                          clarification: MailClarification(prompt: "Say “choose 1” to open it.", options: messages),
                          evidence: ["searched \(query.description)"],
                          message: "Found 1 message: \(messages[0].displayLine).")
        default:
            pending = Pending(intent: intent, candidates: messages, createdAt: .now)
            let senders = Set(messages.map { $0.senderAddress.lowercased() })
            let who = senders.count > 1 && query.sender != nil
                ? " from \(senders.count) different senders (\(Self.distinctNames(messages)))" : ""
            let prompt = "\(messages.count) messages match\(who). Which one? Say a number.\(more)"
            return result(command, .needsClarification, messages: messages, total: found.total,
                          clarification: MailClarification(prompt: prompt, options: messages),
                          evidence: ["searched \(query.description)"], message: prompt)
        }
    }

    static func validate(_ query: MailQuery) throws(MailError) {
        if query.isEmpty { throw .invalidQuery("Say who the message is from, its subject, or what it's about.") }
        let fields = [query.sender, query.subject, query.mailbox].compactMap { $0 } + query.terms
        if fields.contains(where: { $0.count > 200 }) { throw .invalidQuery("That search is too long.") }
        if !(1...100).contains(query.limit) { throw .invalidQuery("The result limit must be 1 to 100.") }
    }

    static func distinctNames(_ messages: [MailMessageSummary]) -> String {
        var seen: [String] = []
        for m in messages {
            let name = m.senderName.isEmpty ? m.senderAddress : "\(m.senderName) <\(m.senderAddress)>"
            if !seen.contains(name) { seen.append(name) }
        }
        return seen.joined(separator: "; ")
    }

    // MARK: Open / read

    /// Spec 02 §9: re-read the message at the reference before acting; refuse if it is
    /// gone or is no longer the message the user chose.
    func revalidate(_ ref: MailMessageRef, expected: MailMessageSummary?) async throws(MailError) -> MailMessageSummary {
        let fresh = try await backend.lookup(ref)
        try Self.check(fresh, ref: ref, expected: expected)
        return fresh
    }

    static func check(_ fresh: MailMessageSummary, ref: MailMessageRef, expected: MailMessageSummary?) throws(MailError) {
        if fresh.ref.messageID != ref.messageID { throw .referenceChanged("a different message is now at that reference") }
        if let expected {
            if fresh.subject != expected.subject { throw .referenceChanged("its subject changed") }
            if fresh.senderAddress.lowercased() != expected.senderAddress.lowercased() { throw .referenceChanged("its sender changed") }
        }
    }

    private func openMessage(_ ref: MailMessageRef, expected: MailMessageSummary?, command: MailCommand) async throws(MailError) -> MailResult {
        let (fresh, observation, evidence) = try await openAndVerify(ref, expected: expected)
        let status = Self.status(for: observation)
        if status != .failed { activeMessage = fresh }
        let message: String
        switch status {
        case .completed: message = "Opened “\(fresh.subject)” from \(fresh.senderName.isEmpty ? fresh.senderAddress : fresh.senderName)."
        case .unverified: message = "Asked Mail to open “\(fresh.subject)”, but I couldn't confirm it on screen."
        default: message = "Mail didn't show “\(fresh.subject)”."
        }
        return result(command, status, opened: fresh, observation: observation, evidence: evidence, message: message)
    }

    private func readMessage(_ ref: MailMessageRef, expected: MailMessageSummary?, command: MailCommand) async throws(MailError) -> MailResult {
        let (fresh, observation, evidence) = try await openAndVerify(ref, expected: expected)
        let status = Self.status(for: observation)
        if status != .failed { activeMessage = fresh }
        let content = try await readBody(fresh)
        let message = status == .completed
            ? "Opened and read “\(fresh.subject)” from \(fresh.senderName.isEmpty ? fresh.senderAddress : fresh.senderName)."
            : "Read “\(fresh.subject)”, but I couldn't confirm Mail is showing it."
        return result(command, status, opened: fresh, observation: observation, content: content, evidence: evidence, message: message)
    }

    private func openAndVerify(_ ref: MailMessageRef, expected: MailMessageSummary?)
        async throws(MailError) -> (MailMessageSummary, MailDisplayObservation, [String])
    {
        let clock = ContinuousClock()
        var mark = clock.now
        var timings: [String] = []
        func lap(_ name: String) {
            let now = clock.now
            let ms = (now - mark).components.seconds * 1000 + (now - mark).components.attoseconds / 1_000_000_000_000_000
            timings.append("\(name) \(ms) ms")
            mark = now
        }
        // Revalidate and fetch the body in one round trip. The first body line (kept in memory
        // only) lets Accessibility confirm the body is actually on screen.
        let (fresh, body) = try await backend.lookupWithContent(ref)
        try Self.check(fresh, ref: ref, expected: expected)
        let snippet = MailContentFormatter.snippet(body)
        lap("revalidate")
        var evidence = ["revalidated: same Message-ID\(expected == nil ? "" : ", subject and sender") at \(ref.mailbox)"]
        let outcome = try await backend.open(fresh.ref, expectedSubject: fresh.subject)
        lap("open")
        let scripted = !fresh.subject.isEmpty && (outcome.frontWindow?.hasPrefix(fresh.subject) ?? false)

        var visible = (windowMatches: false, bodyVisible: false)
        if let verifier {
            let deadline = ContinuousClock.now + configuration.verifyTimeout
            repeat {
                visible = await verifier.observe(subject: fresh.subject, bodySnippet: snippet)
                if visible.windowMatches && (visible.bodyVisible || snippet == nil) { break }
                try? await Task.sleep(for: configuration.pollInterval)
            } while ContinuousClock.now < deadline
        }
        lap("on-screen check")
        let observation = MailDisplayObservation(scriptedWindowMatches: scripted, visibleWindowMatches: visible.windowMatches,
                                                 bodyVisible: visible.bodyVisible)
        evidence.append("Mail's front window is titled with the subject (scripting): \(scripted)")
        evidence.append("window title on screen matches (Accessibility): \(visible.windowMatches)")
        evidence.append("start of the body visible on screen (Accessibility): \(snippet == nil ? "n/a (empty body)" : String(visible.bodyVisible))")

        if !fresh.isRead, outcome.isReadAfter == true {
            evidence.append("Mail marked it as read when it was opened (Mail's normal behaviour; Flow changed no flags)")
        }
        evidence.append("timings: " + timings.joined(separator: ", "))
        return (fresh, observation, evidence)
    }

    static func status(for o: MailDisplayObservation) -> NavigationStatus {
        if o.scriptedWindowMatches && o.visibleWindowMatches && o.bodyVisible { return .completed }
        if o.scriptedWindowMatches || o.visibleWindowMatches { return .unverified }
        return .failed
    }

    private func readBody(_ summary: MailMessageSummary) async throws(MailError) -> MailMessageContent {
        let raw = try await backend.content(summary.ref)
        let (body, truncated) = MailContentFormatter.clean(raw, maxCharacters: configuration.maxBodyCharacters)
        guard !body.isEmpty else { throw .contentUnavailable }
        return MailMessageContent(summary: summary, body: body, truncated: truncated)
    }

    private func result(
        _ command: MailCommand, _ status: NavigationStatus, messages: [MailMessageSummary] = [], total: Int? = nil,
        clarification: MailClarification? = nil, opened: MailMessageSummary? = nil, observation: MailDisplayObservation? = nil,
        content: MailMessageContent? = nil, error: MailError? = nil, evidence: [String] = [], message: String
    ) -> MailResult {
        MailResult(actionID: UUID(), command: command, status: status, messages: messages, totalMatches: total,
                   clarification: clarification, opened: opened, observation: observation, content: content,
                   error: error, evidence: evidence, userMessage: message, timestamp: Date())
    }
}

/// Prepares Mail's plain-text body for reading: no headers or hidden metadata.
public enum MailContentFormatter {
    public static func clean(_ raw: String, maxCharacters: Int) -> (String, Bool) {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Attachment placeholders, zero-width and bidi control characters.
        let invisible: Set<Character> = ["\u{FFFC}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{200E}", "\u{200F}"]
        text = String(text.filter { !invisible.contains($0) })
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var l = line
            while let last = l.last, last == " " || last == "\t" { l.removeLast() }
            return l
        }
        var collapsed: [String] = []
        var blank = 0
        for line in lines {
            blank = line.isEmpty ? blank + 1 : 0
            if blank <= 1 { collapsed.append(line) }
        }
        text = collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxCharacters else { return (text, false) }
        var cut = String(text.prefix(maxCharacters))
        if let space = cut.lastIndex(where: { $0 == " " || $0 == "\n" }) { cut = String(cut[..<space]) }
        return (cut + "…", true)
    }

    /// First non-empty line, up to 40 characters: used only to confirm the body is on screen.
    public static func snippet(_ raw: String) -> String? {
        let (text, _) = clean(raw, maxCharacters: 2_000)
        guard let line = text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(40))
    }
}

extension MailResult {
    /// Human-readable summary for the test UI and `flowctl`. Never includes the body.
    public var report: String {
        var lines = ["[\(status.rawValue)] \(command.name): \(userMessage)"]
        if let clarification {
            lines += clarification.options.enumerated().map { "  \($0.offset + 1). \($0.element.displayLine)" }
        } else if !messages.isEmpty {
            lines += messages.map { "  - \($0.displayLine)" }
        }
        if let opened { lines.append("  message: \(opened.sender) — \(opened.subject) [id \(opened.ref.internalID) in \(opened.ref.mailbox)]") }
        lines += evidence.map { "  \($0)" }
        if let content { lines.append("  body: \(content.body.count) characters\(content.truncated ? " (truncated)" : "")") }
        if let error { lines.append("  error: \(error)") }
        return lines.joined(separator: "\n")
    }
}
