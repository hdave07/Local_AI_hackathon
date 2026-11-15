import FlowMail
import FlowPlanner
import FlowText
import Foundation

/// FlowText's view of a Flow-created Mail reply draft (T-023B, ADR 0010): the authored part
/// of the draft, read exactly through Mail scripting, versioned by `MailDraftController`.
/// Writes are compare-and-set and verified on screen by the controller; quoted text,
/// recipients and subject are never written. Never sends, saves or deletes.
struct MailDraftTextBackend: TextBackend {
    let drafts: MailDraftController
    let draftID: String
    let witness: EditWitness

    func snapshot(_ document: TextDocumentID) async throws(TextBackendError) -> TextSnapshot {
        let r = await drafts.editableText(draftID)
        guard let t = r.text else { throw Self.error(r.error, version: nil) }
        return TextSnapshot(document: document, text: t.authored, version: t.version)
    }

    func apply(_ change: TextChange) async throws(TextBackendError) -> TextSnapshot {
        let live = await drafts.editableText(draftID)
        guard let t = live.text else { throw Self.error(live.error, version: nil) }
        // Revalidate against the live text: never overwrite a change Flow didn't make.
        guard t.version == change.baseVersion, TextSnapshot(document: change.document, text: t.authored, version: t.version).contentHash == change.baseHash
        else { throw .stale(liveVersion: t.version) }
        guard TextChange.apply(change.replacements, to: t.authored) == change.expectedText else {
            throw .failed("The planned change doesn't match the draft.")
        }
        let r = await drafts.replaceAuthored(draftID, baseVersion: t.version, baseText: t.authored, newText: change.expectedText)
        await witness.record(r)
        switch r.status {
        case .completed:
            guard let authored = r.authored, let d = r.draft else { throw .failed("I couldn't read the draft back.") }
            return TextSnapshot(document: change.document, text: authored, version: d.version)
        case .unverified:
            throw .failed(r.userMessage)
        default:
            throw Self.error(r.error, version: r.draft?.version)
        }
    }

    static func error(_ e: MailError?, version: Int?) -> TextBackendError {
        switch e {
        case .draftChanged: .stale(liveVersion: version ?? 0)
        case .draftGone, .unknownDraft: .documentNotFound
        case .some(let e): .failed(e.userMessage)
        case nil: .failed("I couldn't read the draft.")
        }
    }
}

/// Remembers the last write's status, so an edit Mail may have applied but Flow couldn't
/// confirm is reported as unverified, not as a plain failure.
actor EditWitness {
    private(set) var last: MailDraftEditResult?
    func record(_ r: MailDraftEditResult) { last = r }
    func take() -> MailDraftEditResult? { defer { last = nil }; return last }
}
