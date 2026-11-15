import FlowCore
import FlowRouting
import FlowText
import Foundation

/// Scripted stand-in for Track A's executor, for tests and the developer harness.
///
/// It models apps, messages on several channels, drafts and a send log in memory. It
/// executes nothing on macOS. Faults can be injected per capability to exercise failure,
/// ambiguity, staleness, external draft edits and uncertain sends.
public actor MockExecutor: PlanExecuting {
    public struct World: Sendable {
        public var activeApp: KnownApp?
        public var messages: [MessageRef]
        public var drafts: [String: DraftSnapshot] = [:]
        public var sent: [(channel: MessageChannel, draftID: String, hash: String)] = []
        public var epoch = 1
        public var calendarAnswer = "You're free at that time in your accessible calendars."

        public init(activeApp: KnownApp? = nil, messages: [MessageRef] = []) {
            self.activeApp = activeApp
            self.messages = messages
        }
    }

    public enum SendBehavior: Sendable { case succeed, unverified, timeout }

    public private(set) var world: World
    public private(set) var requests: [ExecutionRequest] = []
    private var faults: [Capability: [ExecutionResult]] = [:]
    private var delays: [Capability: Duration] = [:]
    private var sendBehavior: SendBehavior = .succeed
    private var nextDraft = 1
    private let editSessions = DraftEditSessions()

    public init(world: World) {
        self.world = world
    }

    // MARK: Fault injection

    /// The next executions of `capability` return these results, in order.
    public func inject(_ results: [ExecutionResult], for capability: Capability) {
        faults[capability, default: []].append(contentsOf: results)
    }

    public func delay(_ capability: Capability, by duration: Duration) { delays[capability] = duration }
    public func setSendBehavior(_ behavior: SendBehavior) { sendBehavior = behavior }

    /// New result set: earlier message references become stale.
    public func bumpEpoch() {
        world.epoch += 1
        world.messages = world.messages.map {
            MessageRef(channel: $0.channel, id: $0.id, sender: $0.sender, senderAddress: $0.senderAddress, subject: $0.subject,
                       date: $0.date, epoch: world.epoch)
        }
    }

    /// The user edits the draft by hand, outside Flow (new version, new content).
    public func userEditsDraft(_ id: String, body: String) {
        guard let d = world.drafts[id] else { return }
        world.drafts[id] = DraftSnapshot(channel: d.channel, id: d.id, recipients: d.recipients, subject: d.subject, body: body,
                                         version: d.version + 1, inReplyTo: d.inReplyTo)
    }

    public var sendRequests: [ExecutionRequest] { requests.filter { $0.action == .requestSend } }

    // MARK: PlanExecuting

    public func execute(_ request: ExecutionRequest) async -> ExecutionResult {
        requests.append(request)
        let capability = Capability(request.action)
        if let d = delays[capability] {
            do { try await Task.sleep(for: d) } catch {
                return ExecutionResult(status: .cancelled, userMessage: "Cancelled before acting.")
            }
        }
        if var queue = faults[capability], !queue.isEmpty {
            let r = queue.removeFirst()
            faults[capability] = queue
            return r
        }

        switch request.action {
        case .activateApp(let app):
            world.activeApp = app
            return ExecutionResult(status: .completed, observation: .appActive(app))
        case .moveWindow(let w, _), .resizeWindow(let w, _):
            let app: KnownApp? = if case .app(let a) = w { a } else { world.activeApp }
            return ExecutionResult(status: .completed, observation: .window(SelectedWindow(app: app, title: nil, windowID: "w-1")))
        case .tileWindows(let left, _):
            return ExecutionResult(status: .completed, observation: .window(SelectedWindow(app: left, title: nil, windowID: "w-1")))
        case .clickElement(let label), .focus(let label):
            return ExecutionResult(status: .completed, observation: .uiActed(label: label))
        case .scroll:
            return ExecutionResult(status: .completed, observation: .scrolled)
        case .showCalendar(let d):
            return ExecutionResult(status: .completed, observation: .uiActed(label: "Calendar: \(d)"))
        case .queryCalendar:
            return ExecutionResult(status: .completed, observation: .lookupResult(answer: world.calendarAnswer))

        case .readMessage(let query):
            let channel = request.channel ?? .mail
            if let pick = request.bindings.message {
                guard pick.epoch == world.epoch, let live = world.messages.first(where: { $0.id == pick.id }) else {
                    return ExecutionResult(status: .failed, error: .staleTarget, retrySafe: true, userMessage: "The message list changed.")
                }
                return ExecutionResult(status: .completed, observation: .messageOpened(live))
            }
            let found = world.messages.filter { $0.channel == channel && PlanRunner.matches(query: query, $0) }
            switch found.count {
            case 0: return ExecutionResult(status: .failed, error: .targetNotFound, retrySafe: true, userMessage: "I couldn't find that message.")
            case 1: return ExecutionResult(status: .completed, observation: .messageOpened(found[0]))
            default: return ExecutionResult(status: .needsClarification, observation: .messageCandidates(found))
            }

        case .createDraft(let recipient, let content):
            let id = "d-\(nextDraft)"
            nextDraft += 1
            let draft: DraftSnapshot
            if let m = request.bindings.message {
                draft = DraftSnapshot(channel: m.channel, id: id, recipients: [m.senderAddress ?? m.sender],
                                      subject: m.channel == .mail ? "Re: \(m.subject)" : "", body: content, version: 1, inReplyTo: m.id)
            } else {
                draft = DraftSnapshot(channel: request.channel ?? .mail, id: id, recipients: [recipient], body: content, version: 1)
            }
            world.drafts[id] = draft
            return ExecutionResult(status: .completed, observation: .draft(draft))

        case .insertText(let text), .replaceText(_, let text):
            guard let bound = request.bindings.draft else {
                return ExecutionResult(status: .completed, observation: .uiActed(label: text))
            }
            guard let live = world.drafts[bound.id] else {
                return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "The draft is gone.")
            }
            guard live.version == bound.version else {
                return ExecutionResult(status: .failed, error: .draftChanged, userMessage: "The draft changed outside Flow.")
            }
            let body: String
            if case .replaceText(let old, let new) = request.action {
                guard live.body.contains(old) else {
                    return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "I couldn't find “\(old)” in the draft.")
                }
                body = live.body.replacingOccurrences(of: old, with: new)
            } else {
                body = live.body + (live.body.isEmpty ? "" : " ") + text
            }
            let updated = DraftSnapshot(channel: live.channel, id: live.id, recipients: live.recipients, subject: live.subject,
                                        body: body, version: live.version + 1, inReplyTo: live.inReplyTo)
            world.drafts[live.id] = updated
            return ExecutionResult(status: .completed, observation: .draft(updated))

        case .editText(let command):
            guard let bound = request.bindings.draft else {
                return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "There's no draft open to edit.")
            }
            guard world.drafts[bound.id] != nil else {
                return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "The draft is gone.")
            }
            let session = await editSessions.session(for: bound.id) { MockDraftTextBackend(executor: self, draftID: bound.id) }
            return await DraftEditSessions.run(command, in: session) { await self.world.drafts[bound.id] }

        case .requestReview:
            guard let bound = request.bindings.draft, let live = world.drafts[bound.id] else {
                return ExecutionResult(status: .failed, error: .targetNotFound, userMessage: "There's no draft to show.")
            }
            return ExecutionResult(status: .completed, observation: .reviewShown(live))

        case .requestSend:
            // Track A contract: verify the approval against the *live* draft before sending.
            guard let approval = request.bindings.approval, let live = world.drafts[approval.draftID],
                  approval.authorizes(.send, on: live, now: Date())
            else {
                return ExecutionResult(status: .failed, error: .approvalInvalid, userMessage: "The approval doesn't match the draft.")
            }
            switch sendBehavior {
            case .succeed:
                world.sent.append((live.channel, live.id, live.contentHash))
                world.drafts[live.id] = nil
                await editSessions.forget(live.id)
                return ExecutionResult(status: .completed, observation: .sent(draftID: live.id, queued: false))
            case .unverified:
                world.sent.append((live.channel, live.id, live.contentHash))  // it actually went out
                return ExecutionResult(status: .unverified, userMessage: "Send status unknown.")
            case .timeout:
                return ExecutionResult(status: .failed, error: .timeout, userMessage: "The app didn't respond.")
            }
        }
    }
}

// MARK: - Draft text (FlowText backend over the simulated drafts)

extension MockExecutor {
    func draftText(_ id: String) throws(TextBackendError) -> TextSnapshot {
        guard let d = world.drafts[id] else { throw .documentNotFound }
        return TextSnapshot(document: DraftEditSessions.documentID(id), text: d.body, version: d.version)
    }

    /// Compare-and-set, like a real backend: refuses unless the live body is the base.
    func applyDraftText(_ id: String, _ change: TextChange) throws(TextBackendError) -> TextSnapshot {
        guard let d = world.drafts[id] else { throw .documentNotFound }
        let live = TextSnapshot(document: change.document, text: d.body, version: d.version)
        guard live.version == change.baseVersion, live.contentHash == change.baseHash else { throw .stale(liveVersion: d.version) }
        let body = TextChange.apply(change.replacements, to: d.body)
        let updated = DraftSnapshot(channel: d.channel, id: d.id, recipients: d.recipients, subject: d.subject, body: body,
                                    version: d.version + 1, inReplyTo: d.inReplyTo)
        world.drafts[id] = updated
        return TextSnapshot(document: change.document, text: body, version: updated.version)
    }
}

struct MockDraftTextBackend: TextBackend {
    let executor: MockExecutor
    let draftID: String

    func snapshot(_ document: TextDocumentID) async throws(TextBackendError) -> TextSnapshot {
        try await executor.draftText(draftID)
    }

    func apply(_ change: TextChange) async throws(TextBackendError) -> TextSnapshot {
        try await executor.applyDraftText(draftID, change)
    }
}
