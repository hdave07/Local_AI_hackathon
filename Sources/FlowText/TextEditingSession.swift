import FlowCore
import Foundation

/// One applied Flow edit, kept for targeted undo.
public struct EditRecord: Sendable, Equatable {
    public let summary: String
    public let baseText: String
    public let baseVersion: Int
    public let resultText: String
    public let resultVersion: Int
    /// Each replacement's span in the *result* text and the text it replaced.
    public let resultSpans: [(range: TextRange, inserted: String, removed: String)]

    public static func == (a: EditRecord, b: EditRecord) -> Bool {
        a.summary == b.summary && a.baseVersion == b.baseVersion && a.resultVersion == b.resultVersion
            && a.resultText == b.resultText && a.resultSpans.map(\.range) == b.resultSpans.map(\.range)
    }
}

public struct AppliedEdit: Sendable, Equatable {
    public let summary: String
    public let snapshot: TextSnapshot
    /// Changed span in `snapshot.text` (highlight; FlowRouting `lastEditedText` source).
    public let changedRange: TextRange
    public var changedText: String { (snapshot.text as NSString).substring(with: NSRange(location: changedRange.location, length: changedRange.length)) }
}

public struct EditPreview: Sendable, Equatable {
    public let summary: String
    public let before: String
    public let after: String
    /// Names, dates, times, numbers, links the change would drop or add.
    public let missingFacts: [String]
    public let addedFacts: [String]

    public var prompt: String {
        var p = "Here's the change: “\(after)”."
        if !missingFacts.isEmpty { p += " It drops \(missingFacts.joined(separator: ", "))." }
        if !addedFacts.isEmpty { p += " It adds \(addedFacts.joined(separator: ", "))." }
        return p + " Keep it, or discard it?"
    }
}

public enum EditOutcome: Sendable, Equatable {
    case applied(AppliedEdit)
    case undone(AppliedEdit)
    /// Several matches (or meanings): answer with a number, "the last one", or "all of them".
    case choose(prompt: String, options: [String])
    /// A substantial change waits for "keep it" / "discard it".
    case preview(EditPreview)
    case discarded
    case dictationStarted
    case dictationEnded
    /// stop / cancel: dictation ends, open questions are dropped, nothing more is applied.
    case cancelled
    case refused(String)
    case notFound(String)
    case nothingToUndo
    /// Not an editing request; route it elsewhere (planner, router).
    case notHandled
    case failed(String)
}

/// Voice editing of one text document (spec 02 §12; T-025).
///
/// Every edit is planned against a **fresh** snapshot and applied with that snapshot's
/// version and hash, so the backend refuses rather than overwrite external changes. The
/// result is verified to be exactly the planned text. In dictation mode every utterance is
/// literal text except stop/cancel/"stop dictation" (FlowCore `DeterministicRouter`).
/// This actor never sends, saves or deletes a document.
public actor TextEditingSession {
    public enum Mode: Sendable, Equatable {
        case command
        case dictation
    }

    public let document: TextDocumentID
    public private(set) var mode: Mode = .command
    public private(set) var history: [EditRecord] = []

    private let backend: any TextBackend
    private let rewriter: (any RewriteGenerating)?
    private var pendingChoice: (choice: OccurrenceChoice, op: EditOperation)?
    private var pendingPreview: EditPlan?
    private var pendingFacts: (missing: [String], added: [String]) = ([], [])
    /// Bumped by stop/cancel: an edit planned before it is not applied after it.
    private var generation = 0

    public static let maxHistory = 20

    public init(document: TextDocumentID, backend: any TextBackend, rewriter: (any RewriteGenerating)? = nil) {
        self.document = document
        self.backend = backend
        self.rewriter = rewriter
    }

    public var hasOpenQuestion: Bool { pendingChoice != nil || pendingPreview != nil }

    // MARK: Entry point

    public func handle(_ utterance: String) async -> EditOutcome {
        // 1. Control phrases first, in every mode, without any model.
        if let control = DeterministicRouter.route(utterance)?.control {
            switch control {
            case .stop, .cancel:
                generation += 1
                let wasBusy = mode == .dictation || hasOpenQuestion
                mode = .command
                pendingChoice = nil
                pendingPreview = nil
                return wasBusy ? .cancelled : .notHandled  // nothing of ours to stop: let the caller cancel its work
            case .stopDictation:
                guard mode == .dictation else { return .notHandled }
                mode = .command
                return .dictationEnded
            }
        }

        // 2. Literal dictation: ordinary words are text, even "delete the last sentence".
        if mode == .dictation {
            let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .refused("I didn't hear any words.") }
            return await perform(.insert(text))
        }

        // 3. Answers to an open question.
        if let pending = pendingChoice, let picked = Self.pick(utterance, count: pending.choice.options.count) {
            pendingChoice = nil
            return await resolve(pending, picked)
        }
        if pendingPreview != nil, let yes = Self.yesNo(utterance) {
            let plan = pendingPreview!
            pendingPreview = nil
            return yes ? await applyPreviewed(plan) : .discarded
        }

        // 4. Editing commands.
        switch EditCommandParser.parse(utterance) {
        case .control: return .notHandled  // handled above
        case .startDictation(let initial):
            mode = .dictation
            if let initial, !initial.isEmpty { return await perform(.insert(initial)) }
            return .dictationStarted
        case .refused(let why): return .refused(why)
        case .notAnEdit:
            // An unrelated command drops an open question rather than answering it wrongly.
            pendingChoice = nil
            pendingPreview = nil
            return .notHandled
        case .edit(let op):
            pendingChoice = nil
            pendingPreview = nil
            return await perform(op)
        }
    }

    // MARK: Operations

    private func perform(_ op: EditOperation) async -> EditOutcome {
        switch op {
        case .undo: return await undo()
        case .rewrite(let style): return await rewrite(style)
        default: break
        }
        let snap: TextSnapshot
        do throws(TextBackendError) { snap = try await backend.snapshot(document) } catch { return Self.outcome(error) }
        switch TextEditor.plan(op, on: snap) {
        case .plan(let plan):
            if plan.requiresPreview {
                pendingPreview = plan
                pendingFacts = ([], [])
                return .preview(EditPreview(summary: plan.summary, before: plan.before, after: plan.after, missingFacts: [], addedFacts: []))
            }
            return await apply(plan)
        case .choose(let choice):
            pendingChoice = (choice, op)
            return .choose(prompt: choice.prompt, options: choice.options)
        case .notFound(let why): return .notFound(why)
        case .nothingToDo(let why): return .refused(why)
        }
    }

    private func resolve(_ pending: (choice: OccurrenceChoice, op: EditOperation), _ picked: [Int]) async -> EditOutcome {
        let snap: TextSnapshot
        do throws(TextBackendError) { snap = try await backend.snapshot(document) } catch { return Self.outcome(error) }
        // The text changed while the user was choosing: plan again on the live text.
        guard snap.version == pending.choice.baseVersion else { return await perform(pending.op) }
        if case .split(let olds) = pending.choice.kind, let i = picked.first, olds.indices.contains(i),
           case .replace(let candidates, let occ) = pending.op
        {
            return await perform(.replace(candidates: candidates.filter { $0.old == olds[i] }, occ))
        }
        switch TextEditor.plan(choice: pending.choice, picking: picked, on: snap) {
        case .plan(let plan): return plan.requiresPreview ? previewing(plan) : await apply(plan)
        case .choose(let c):
            pendingChoice = (c, pending.op)
            return .choose(prompt: c.prompt, options: c.options)
        case .notFound(let why): return .notFound(why)
        case .nothingToDo(let why): return .refused(why)
        }
    }

    private func previewing(_ plan: EditPlan) -> EditOutcome {
        pendingPreview = plan
        return .preview(EditPreview(summary: plan.summary, before: plan.before, after: plan.after, missingFacts: [], addedFacts: []))
    }

    private func applyPreviewed(_ plan: EditPlan) async -> EditOutcome {
        // Re-validate: the preview was made against a specific version.
        let snap: TextSnapshot
        do throws(TextBackendError) { snap = try await backend.snapshot(document) } catch { return Self.outcome(error) }
        guard snap.version == plan.change.baseVersion, snap.contentHash == plan.change.baseHash else {
            return .refused("The text changed after the preview, so I didn't apply it.")
        }
        return await apply(plan)
    }

    private func apply(_ plan: EditPlan) async -> EditOutcome {
        let myGeneration = generation
        let result: TextSnapshot
        do throws(TextBackendError) { result = try await backend.apply(plan.change) } catch { return Self.outcome(error) }
        guard result.text == plan.change.expectedText, result.version > plan.change.baseVersion else {
            return .failed("The text didn't end up as expected, so I stopped. Nothing else was changed.")
        }
        record(plan, result)
        // stop/cancel arrived while the edit was being applied: it is committed (and undoable),
        // but nothing further runs.
        if myGeneration != generation { return .cancelled }
        return .applied(AppliedEdit(summary: plan.summary, snapshot: result, changedRange: plan.changedRange))
    }

    private func record(_ plan: EditPlan, _ result: TextSnapshot) {
        var spans: [(TextRange, String, String)] = []
        var shift = 0
        let base = plan.before as NSString
        for r in plan.change.replacements.sorted(by: { $0.range.location < $1.range.location }) {
            let newLen = (r.text as NSString).length
            spans.append((TextRange(location: r.range.location + shift, length: newLen), r.text, base.substring(with: r.range.ns)))
            shift += newLen - r.range.length
        }
        history.append(EditRecord(summary: plan.summary, baseText: plan.before, baseVersion: plan.change.baseVersion,
                                  resultText: result.text, resultVersion: result.version,
                                  resultSpans: spans.map { (range: $0.0, inserted: $0.1, removed: $0.2) }))
        if history.count > Self.maxHistory { history.removeFirst(history.count - Self.maxHistory) }
    }

    // MARK: Undo (targeted)

    /// Undoes Flow's most recent edit. Works after unrelated changes elsewhere in the text;
    /// refuses if the edited span itself was changed since.
    private func undo() async -> EditOutcome {
        guard let last = history.last else { return .nothingToUndo }
        let live: TextSnapshot
        do throws(TextBackendError) { live = try await backend.snapshot(document) } catch { return Self.outcome(error) }
        guard let spans = Self.map(last, onto: live.text) else {
            return .refused("The text around that change was edited since, so I can't undo it safely.")
        }
        let replacements = spans.map { Replacement(range: $0.range, text: $0.removed) }
        let expected = TextChange.apply(replacements, to: live.text)
        let change = TextChange(document: document, baseVersion: live.version, baseHash: live.contentHash,
                                replacements: replacements, expectedText: expected,
                                caretAfter: spans.last.map { TextRange(location: $0.range.location + ($0.removed as NSString).length, length: 0) })
        let result: TextSnapshot
        do throws(TextBackendError) { result = try await backend.apply(change) } catch { return Self.outcome(error) }
        guard result.text == expected else { return .failed("The undo didn't produce the expected text, so I stopped.") }
        history.removeLast()
        let first = spans.first!.range.location
        return .undone(AppliedEdit(summary: "Undid: \(last.summary)", snapshot: result,
                                   changedRange: TextRange(location: first, length: (spans.first!.removed as NSString).length)))
    }

    /// The record's spans located in `live`, even if the user changed other parts of the text.
    ///
    /// Each span is found by its own text plus surrounding context from the edited result,
    /// from wide context down to one character on each side; the match must be unique. If the
    /// span or its immediate neighbors changed, it is not found and undo is refused.
    static func map(_ record: EditRecord, onto live: String) -> [(range: TextRange, inserted: String, removed: String)]? {
        if record.resultText == live { return record.resultSpans }
        let old = record.resultText as NSString, now = live as NSString
        var mapped: [(range: TextRange, inserted: String, removed: String)] = []
        for s in record.resultSpans {
            var located: Int?
            for k in [32, 16, 8, 4, 2, 1] {
                let leftLen = min(k, s.range.location), rightLen = min(k, old.length - s.range.end)
                let left = old.substring(with: NSRange(location: s.range.location - leftLen, length: leftLen))
                let right = old.substring(with: NSRange(location: s.range.end, length: rightLen))
                let hits = exactOccurrences(of: left + s.inserted + right, in: now)
                if hits.count == 1 { located = hits[0] + (left as NSString).length; break }
                if hits.count > 1 { return nil }  // repeated context: ambiguous, never guess
            }
            guard let location = located else { return nil }
            mapped.append((TextRange(location: location, length: s.range.length), s.inserted, s.removed))
        }
        // Spans must stay in order and not overlap.
        for (a, b) in zip(mapped, mapped.dropFirst()) where a.range.end > b.range.location { return nil }
        return mapped
    }

    static func exactOccurrences(of needle: String, in hay: NSString) -> [Int] {
        guard !needle.isEmpty else { return [] }
        var result: [Int] = []
        var from = 0
        while from <= hay.length {
            let r = hay.range(of: needle, options: [.literal], range: NSRange(location: from, length: hay.length - from))
            guard r.location != NSNotFound else { break }
            result.append(r.location)
            from = r.location + 1
        }
        return result
    }

    // MARK: Rewrites (always previewed, fact-checked)

    private func rewrite(_ style: RewriteStyle) async -> EditOutcome {
        guard let rewriter else { return .refused("Rewriting isn't available yet. You can change specific words instead.") }
        let snap: TextSnapshot
        do throws(TextBackendError) { snap = try await backend.snapshot(document) } catch { return Self.outcome(error) }
        guard !snap.text.isEmpty, let proposed = await rewriter.rewrite(snap.text, style: style),
              !proposed.isEmpty, proposed != snap.text
        else { return .refused("I couldn't produce a different version.") }
        let full = TextRange(location: 0, length: (snap.text as NSString).length)
        let plan = TextEditor.make(snap, [Replacement(range: full, text: proposed)], summary: "Rewrote (\(style.rawValue))")
        let facts = FactCheck.compare(original: snap.text, proposed: proposed)
        pendingPreview = plan
        pendingFacts = facts
        return .preview(EditPreview(summary: plan.summary, before: snap.text, after: proposed,
                                    missingFacts: facts.missing, addedFacts: facts.added))
    }

    // MARK: Answers

    /// "the second one", "2", "number two", "the last one", "both", "all of them".
    static func pick(_ utterance: String, count: Int) -> [Int]? {
        let w = utterance.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let set = Set(w)
        if !set.isDisjoint(with: ["all", "both", "every", "everywhere"]) { return Array(0..<count) }
        if set.contains("last") { return [count - 1] }
        let ordinals = ["first": 0, "one": 0, "1": 0, "second": 1, "two": 1, "2": 1, "third": 2, "three": 2, "3": 2,
                        "fourth": 3, "four": 3, "4": 3, "fifth": 4, "five": 4, "5": 4]
        // Only short answers: a full sentence with a number in it is a new command.
        guard w.count <= 4 else { return nil }
        for word in w { if let i = ordinals[word], i < count { return [i] } }
        return nil
    }

    static func yesNo(_ utterance: String) -> Bool? {
        let w = Set(utterance.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        if !w.isDisjoint(with: ["discard", "no", "nope", "don't", "dont", "original", "revert"]) { return false }
        if !w.isDisjoint(with: ["keep", "yes", "yeah", "apply", "accept", "use", "ok", "okay", "sure"]) { return true }
        return nil
    }

    static func outcome(_ error: TextBackendError) -> EditOutcome {
        switch error {
        case .stale: .refused("The text changed outside Flow, so I didn't change anything. Say it again if you still want it.")
        case .documentNotFound: .failed("That text isn't open anymore.")
        case .notEditable(let why): .refused(why)
        case .failed(let why): .failed(why)
        }
    }
}
