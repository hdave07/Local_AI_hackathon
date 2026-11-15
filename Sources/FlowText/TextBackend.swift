import Foundation

public enum TextBackendError: Error, Sendable, Equatable {
    /// The live text is not the base the change was planned against (changed outside Flow).
    case stale(liveVersion: Int)
    case documentNotFound
    /// The field cannot be edited (secure field, read-only, focus lost).
    case notEditable(String)
    case failed(String)
}

/// The boundary to a real editable text (Track A implements this for Mail drafts,
/// Messages compose fields, Notes, and generic Accessibility text fields; ADR 0009).
///
/// Contract:
/// - `snapshot` re-reads the **live** text and its version.
/// - `apply` must re-read the live text first and throw `.stale` unless it equals
///   `change.baseHash` (and `baseVersion`); it must never overwrite external changes.
///   It then applies the replacements, re-reads, and returns the new snapshot (version
///   increased). Flow verifies the returned text equals `change.expectedText`.
/// - Never sends, saves, submits or deletes the document.
public protocol TextBackend: Sendable {
    func snapshot(_ document: TextDocumentID) async throws(TextBackendError) -> TextSnapshot
    func apply(_ change: TextChange) async throws(TextBackendError) -> TextSnapshot
}

/// Simulated editable texts (a Mail draft body, a chat compose field, a text field) for
/// tests and harnesses. Executes nothing on macOS.
public actor SimulatedTextBackend: TextBackend {
    public struct Document: Sendable, Equatable {
        public var text: String
        public var version: Int
        public var selection: TextRange?
        public var editable: Bool
    }

    public private(set) var documents: [TextDocumentID: Document] = [:]
    public private(set) var applied: [TextChange] = []
    private var applyDelay: Duration?
    /// Applies the edit but reports different text (a misbehaving field), for verification tests.
    private var corruptNextApply = false

    public init() {}

    public func create(_ id: TextDocumentID, text: String, editable: Bool = true, caretAtEnd: Bool = true) {
        let caret = caretAtEnd ? TextRange(location: (text as NSString).length, length: 0) : nil
        documents[id] = Document(text: text, version: 1, selection: caret, editable: editable)
    }

    /// The user (or another app) changes the text outside Flow.
    public func externalEdit(_ id: TextDocumentID, text: String) {
        guard var d = documents[id] else { return }
        d.text = text
        d.version += 1
        documents[id] = d
    }

    public func moveCaret(_ id: TextDocumentID, to range: TextRange) {
        documents[id]?.selection = range
    }

    public func setApplyDelay(_ d: Duration?) { applyDelay = d }
    public func corruptNext() { corruptNextApply = true }

    public func text(_ id: TextDocumentID) -> String? { documents[id]?.text }

    public func snapshot(_ document: TextDocumentID) async throws(TextBackendError) -> TextSnapshot {
        guard let d = documents[document] else { throw .documentNotFound }
        return TextSnapshot(document: document, text: d.text, version: d.version, selection: d.selection)
    }

    public func apply(_ change: TextChange) async throws(TextBackendError) -> TextSnapshot {
        if let applyDelay {
            do { try await Task.sleep(for: applyDelay) } catch { throw .failed("cancelled") }
        }
        guard var d = documents[change.document] else { throw .documentNotFound }
        guard d.editable else { throw .notEditable("This field can't be edited.") }
        // Revalidate against the live text: never overwrite a change Flow didn't make.
        guard d.version == change.baseVersion, TextSnapshot.hash(d.text) == change.baseHash else {
            throw .stale(liveVersion: d.version)
        }
        var result = TextChange.apply(change.replacements, to: d.text)
        if corruptNextApply {
            corruptNextApply = false
            result += " (autocorrected)"
        }
        d.text = result
        d.version += 1
        d.selection = change.caretAfter
        documents[change.document] = d
        applied.append(change)
        return TextSnapshot(document: change.document, text: d.text, version: d.version, selection: d.selection)
    }
}
