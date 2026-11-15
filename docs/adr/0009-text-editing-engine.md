# ADR 0009 — Text-editing engine and its integration interface (T-025)

**Status:** Proposed (needs Track A agreement for §3–§4) · **Date:** 2026-11-15 · **Branch:** `feature/text-editing` · **Owner:** Track B

## Context
Flow can create and review real Mail reply drafts (ADR 0007 addendum), but `insert_text` / `replace_text` are `unsupported` in `MacPlanExecutor`, and there is no dictation. Spec 02 §12 requires exact replacements, last-sentence deletion, append, undo, occurrence disambiguation, versioning, and previewed rewrites with factual-slot protection. The same engine should later serve Mail, Messages, Notes and generic Accessibility text fields.

**This branch adds only the new module `FlowText`** (+ tests, + 6 lines in `Package.swift`). It changes nothing in FlowCore, FlowPlanner, FlowRouting, FlowMail, FlowAX, FlowApp or FlowExecutor, and is not wired into macOS.

## Decision 1 — `FlowText` (Track B)
| Type | Role |
|---|---|
| `TextSnapshot` | Document ID, **exact** text, version, optional caret/selection (UTF-16 ranges, as in AppKit and AX), SHA-256 of the exact text |
| `EditCommandParser` | Deterministic, with no model: append ("add that …", "also say …"), prepend, insert ("type …"), replace ("change A to B", "replace A with B", ordinals, "every …", quoted operands), delete (last/first sentence, last word, phrase), undo ("undo that change", "scratch that"), rewrite styles, start dictation. Refuses deleting the whole draft or message. stop/cancel/stop dictation use FlowCore `DeterministicRouter`. |
| `TextEditor` (pure) | Plans against a snapshot. Token-boundary matching ("3" never matches inside "3:30"). Duplicates produce an `OccurrenceChoice` with bracketed context (never guessed). An ambiguous " to " split is resolved by which old text exists. Minimal spacing; every other character is preserved. |
| `TextEditingSession` (actor, one document) | Command and **dictation** modes. Every edit is planned on a fresh snapshot and applied with `baseVersion` + `baseHash`. The result must equal `expectedText` exactly. Bounded history gives **targeted undo**, located by context so it still works after unrelated external edits, and refuses if the edited span changed. **Previews** for rewrites and large deletions; explicit replacements and insertions are targeted edits applied with undo (PRD D-011). |
| `FactCheck` | Names, times, dates, numbers, money, emails and URLs a rewrite would drop or add, shown in the preview |
| `RewriteGenerating` | Protocol for a future rewrite source (Bonsai). Its output is only ever previewed. |
| `SimulatedTextBackend` | In-memory documents with external edits, delays, read-only fields and corruption, for tests |

**State:** The engine keeps per-document *edit history* only. *Which* document is current stays in FlowRouting's `ConversationContext` (`draft`, `selectedWindow`, `lastEditedText`). No second task-context store.

## Decision 2 — the interface Track A implements
```swift
public protocol TextBackend: Sendable {
    func snapshot(_ document: TextDocumentID) async throws(TextBackendError) -> TextSnapshot
    func apply(_ change: TextChange) async throws(TextBackendError) -> TextSnapshot
}
// TextChange: document, baseVersion, baseHash, replacements [Replacement(range: UTF-16, text)],
//             expectedText, caretAfter
// TextBackendError: .stale(liveVersion), .documentNotFound, .notEditable(why), .failed(why)
```
**Requirements for every backend:**
1. `snapshot` re-reads the **live** text. `version` increases on *any* change, including the user's typing.
2. `apply` re-reads first and throws `.stale` unless the live text hashes to `baseHash`. **Never overwrite external changes.**
3. Apply the replacements (from the end backwards), re-read, and return the new snapshot. Flow verifies `text == expectedText`.
4. **Never send, save, submit or delete.** Secure and password fields must be `.notEditable` and must never be read into snapshots (PRD §9).

| Backend (Track A) | Snapshot source | Apply via | Notes |
|---|---|---|---|
| **Mail draft** | `MailComposeView.body` (AX) + `MailDraftState.version` | AX `kAXValueAttribute`, or set `kAXSelectedTextRangeAttribute` then `kAXSelectedTextAttribute` (preserves undo in Mail) | Bump `MailDraftState.version` on every change, so the planner's send approval (ADR 0005) is invalidated automatically |
| **Generic AX text field / Notes** | `kAXValueAttribute`, `kAXSelectedTextRangeAttribute` | same | Reject `AXSecureTextField`; revalidate the element identity (FlowAX snapshot epoch) |
| **Messages / WhatsApp compose field** | AX value of the compose field | AX set value | The compose field is the draft (ADR 0005 Q1) |

## Decision 3 — proposed planner/executor integration (needs agreement; not implemented)
- **Option A (no FlowCore change):** `MacPlanExecutor` handles `insert_text` / `replace_text` for a bound draft by running FlowText against a Mail `TextBackend`, and returns `.draft(DraftSnapshot)` with the new version.
- **Option B (FlowCore change):** add `FlowAction.editText(utterance: String)` (deterministic, not model-emittable), so delete, undo, occurrence choice and dictation reach FlowText intact. `replace_text` / `insert_text` cannot express "remove the last sentence", "undo" or "the second one".
- **Dictation mode** in the voice session: while a FlowText session is in `.dictation`, the coordinator sends finalized utterances to `TextEditingSession.handle` *before* `TaskSession`. Only stop/cancel/stop dictation stay commands.
- **Occurrence choices and previews** should use the generic choice observation proposed in ADR 0005 §4, so a plan can pause on them.

## Open questions
1. Option A or B for planner integration?
2. Mail's own undo stack: should backends apply edits as a single undoable Mail operation, so Cmd-Z also works?
3. Where does the caret go after Flow's edit: end of the change (current) or the user's previous position?
4. Rewrite source: Bonsai 2B prompt for formal/shorter/friendlier, gated by `FactCheck` and the preview.
