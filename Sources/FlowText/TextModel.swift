import CryptoKit
import Foundation

/// Identity of an editable text: a Mail draft, a Messages compose field, a Notes body, or
/// an accessible text field. The string form is chosen by the backend ("mail-draft:d-1",
/// "ax:com.apple.Notes/…"). The task-context store (FlowRouting `ConversationContext`)
/// says *which* document is current; FlowText only edits it.
public struct TextDocumentID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// A range in UTF-16 code units (the unit used by `NSString`, AppKit and Accessibility
/// `kAXSelectedTextRange`), so backends can apply it without conversion.
public struct TextRange: Sendable, Equatable, Hashable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }
    var ns: NSRange { NSRange(location: location, length: length) }
}

/// The text exactly as the backend read it, with its version.
public struct TextSnapshot: Sendable, Equatable {
    public let document: TextDocumentID
    public let text: String
    /// Increases with every change, including changes made outside Flow.
    public let version: Int
    /// Caret or selection, if the backend knows it (dictation inserts there).
    public let selection: TextRange?

    public init(document: TextDocumentID, text: String, version: Int, selection: TextRange? = nil) {
        self.document = document
        self.text = text
        self.version = version
        self.selection = selection
    }

    /// SHA-256 of the exact text (no normalization: the user's characters are the contract).
    public var contentHash: String { TextSnapshot.hash(text) }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One replacement in base-text coordinates.
public struct Replacement: Sendable, Equatable {
    public let range: TextRange
    public let text: String

    public init(range: TextRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// What Flow asks a backend to apply: replacements against an exact base state, and the
/// exact text that must result. Backends refuse if the live text is not the base.
public struct TextChange: Sendable, Equatable {
    public let document: TextDocumentID
    public let baseVersion: Int
    public let baseHash: String
    /// Non-overlapping, in base coordinates (applied from the end backwards).
    public let replacements: [Replacement]
    public let expectedText: String
    /// Where the caret should be afterwards (end of the change).
    public let caretAfter: TextRange?

    public init(document: TextDocumentID, baseVersion: Int, baseHash: String, replacements: [Replacement], expectedText: String,
                caretAfter: TextRange? = nil) {
        self.document = document
        self.baseVersion = baseVersion
        self.baseHash = baseHash
        self.replacements = replacements
        self.expectedText = expectedText
        self.caretAfter = caretAfter
    }

    /// Applies replacements to `base` (pure; used by planning, simulation and verification).
    public static func apply(_ replacements: [Replacement], to base: String) -> String {
        let s = NSMutableString(string: base)
        for r in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            s.replaceCharacters(in: r.range.ns, with: r.text)
        }
        return s as String
    }
}
