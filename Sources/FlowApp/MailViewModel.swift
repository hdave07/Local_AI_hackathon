import FlowAX
import FlowMail
import Foundation
import Observation

/// Typed test interface for FlowMail inside the app: MailCommandParser → MailController,
/// the same path as `flowctl` and the live tests. Classifier output is not connected.
/// Message bodies are shown in the UI only; they are never logged or persisted.
@MainActor
@Observable
final class MailViewModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let input: String
        let status: NavigationStatus?
        let text: String
    }

    var command = ""
    private(set) var isRunning = false
    private(set) var log: [LogEntry] = []
    private(set) var candidates: [MailMessageSummary] = []
    private(set) var reading: MailMessageContent?
    private(set) var statusLine = "Mail status not checked yet."

    private let controller: MailController

    init(controller: MailController) {
        self.controller = controller
    }

    var activeMessage: MailMessageSummary? { controller.activeMessage }

    func submit() {
        let text = command
        Task { await run(text) }
    }

    func checkStatus(request: Bool) async {
        let result = await controller.perform(.status(requestPermission: request))
        statusLine = result.userMessage
    }

    func run(_ text: String) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let entry: LogEntry
        do throws(MailParseError) {
            let result = await controller.perform(try MailCommandParser.parse(text))
            entry = LogEntry(input: text, status: result.status, text: result.report)
            if let content = result.content { reading = content }
            if case .status = result.command { statusLine = result.userMessage }
        } catch {
            entry = LogEntry(input: text, status: nil, text: error.message)
        }
        candidates = controller.candidates
        log.insert(entry, at: 0)
        if log.count > 50 { log.removeLast() }
    }
}
