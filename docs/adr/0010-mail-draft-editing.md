# ADR 0010 — Voice editing of Mail reply drafts (T-023B)

**Status:** Proposed. §1 changes the FlowCore contract and needs Track A acknowledgement. · **Date:** 2026-11-15 · **Branch:** `feature/mail-draft-editing` · **Resolves:** ADR 0009 open question 1 (Option B)

## Context
T-023A creates and reviews real Mail reply drafts. T-025 added FlowText, a deterministic editing engine that runs against a `TextBackend`. T-023B connects the two, so spoken edits ("change 3:30 to 4", "remove the last sentence", "undo that change") change the draft Flow created and verified.

The T-023A controller also matched compose windows by title. Two windows titled "Re: [FlowTest] Meeting tomorrow" were either rejected or treated as the same draft.

## Decision 1: a new allowlisted action, `edit_text` (FlowCore)
- `FlowAction.editText(String)` carries the user's edit command verbatim, minus the wake word, discourse openers and fillers. It is `risk: .content` and `isTextAction`.
- **Deterministic only.** `ActionType.modelEmittable` excludes it, so the Bonsai schema never offers it, and `IntentValidator` rejects model output that names it (`unsupportedAction`).
- **Why not reuse `replace_text`/`insert_text`?** They can't express "remove the last sentence", "undo that change", "the second one" or "keep it" (ADR 0009 §3).

## Decision 2: routing (FlowRouting)
- **The rule.** `Rules.draftEdit` runs after draft discard and draft review, and before "unsupported" (so "remove…" isn't declined as "deleting"). It fires when FlowText's `EditCommandParser` returns `.edit` and the context has a draft.
  - Appends need an unmistakable phrasing ("add that…", "also say…"), so "Add Sarah to the meeting" never becomes draft text.
  - "What does the draft say?" stays `request_review`.
- **No draft.** Append, delete and undo get a question ("There's no draft open to edit…"). Replace and rewrite keep their existing routing.
- **Questions.** When FlowText asks (which occurrence, keep or discard a preview), the question is stored as `PendingQuestion.textEdit` in the existing `ConversationContext`. A short answer ("the second one", "all of them", "keep it") routes back as `edit_text`. Anything else drops the question. Stop and cancel clear it. **There is no second context store.**
- **Clause splitting.** The planner drops a leading opener clause ("Actually,"). The utterance's final punctuation is restored on the last `edit_text` clause, so appended sentences keep their period.

## Decision 3: planning and verification (FlowPlanner)
- An `edit_text` step binds the current draft (from the plan or the context; precondition `draftExists`) and expects **`.draftEdited`**.
- Verification requires the observation to be `.draft` with the *same draft id* on the same channel. An open compose window is never accepted as proof.
- **Each edit bumps the draft version.** The ADR 0005 approval hash therefore stops matching, and a send needs a new review.
- **Clarification.** `Observation.textChoice(prompt, options)` makes the runner set the `textEdit` pending question and stop with the prompt. The spoken-feedback phase becomes `awaitingAnswer`.
- **Shared mapping.** `DraftEditSessions` maps FlowText outcomes to `ExecutionResult` for both `MockExecutor` and `MacPlanExecutor`. It also holds one `TextEditingSession` per draft (undo history only).
- **Read-back.** It reports what was verified: "Here's the draft. It says: “…”".

## Decision 4: the Mail backend (FlowMail + FlowExecutor)
**Source of truth: Mail scripting `content`.** It is exact plain text and settable. Accessibility is the independent on-screen check.

**Exact text.** `MailDraftController.editableText(id)` re-reads the live draft, then splits it with `AuthoredText`: the authored part above "On … wrote:", "-----Original Message-----" or "> " lines, and the quoted original. Any difference from the last text Flow read or wrote bumps the version.

**`replaceAuthored(id, baseVersion, baseText, newText)`** writes like this:
1. Refuse unless the live version and authored text still equal the base (`draftChanged`).
2. **Compare-and-set** in JXA (`setDraftContent`). It writes only if exactly one open draft has this subject, these To recipients (no Cc or Bcc) and *exactly* the expected text. It returns `written`, `changed`, `notFound` or `ambiguous(n)`. Only `content` is set: never recipients, subject or headers, and nothing is sent, saved or closed.
3. Verify. The scripting read-back must equal the new authored text plus the *unchanged* quote, and the same compose window must show the new text, still addressed only to the sender with no Cc. Otherwise the result is `unverified`.
4. A timeout is reported as `unverified`. The next read compares the live text and tells the truth.

**Executor wiring.** `MailDraftTextBackend` is FlowText's `TextBackend` over the controller. `MacPlanExecutor` handles `edit_text` only for Flow-created drafts in the FlowTest scope, and only when **`ExecutorConfiguration.allowMailDraftEditing`** is on. **It defaults to off**, because this path hasn't run against real Mail yet.

## Decision 5: compose windows are never matched by title alone
`MailDraftController.select(views, token:, names:, require:, prefer:)` is used by creation, review and editing:
1. **Window identity wins.** `MailComposeView.windowToken` is the `CFHash` of the window's `AXUIElement`. A known token decides, even if the user then edits recipients, which is reported as a version change.
2. **Otherwise only strict matches count.** That means windows with one To token naming the sender, no Cc, and (when creating) the requested text. If several remain, the body equal to the last verified body breaks the tie.
3. **Equal matches are `draftAmbiguous(n)`.** Flow never guesses and never uses "the first window".

Scripting applies the same rule. Several open drafts with one subject are told apart by recipients, then by exact text; equal candidates are ambiguous. If creation finds two equal windows, it fails with `draftAmbiguous`, is still registered under the step key, and never creates another draft on retry.

## Alternatives considered
- **AX `kAXValueAttribute` / selected-text replacement on the body.**
  - Pro: it would keep Mail's own undo stack (ADR 0009 Q2).
  - Con: the body is an `AXWebArea`. Whether its text is settable, and how rich text and quotes survive, is unknown. `probeComposeBodyAccessibility` (live, gated) reports settability and is the evidence needed to choose it later.
  - Con: it also can't do an atomic compare-and-set.
- **Recreate the draft with the new text.** Rejected. It deletes or discards a draft the user can see and risks duplicates.

## Risks and open questions (need a live run)
1. **Quoted original and formatting.** Does setting `content` on a reply keep the quoted original and its formatting (blue quote bar, signatures, rich text)? The text is preserved byte for byte, but styling may not be. If it isn't kept, use the AX path or edit only plain-text replies.
2. **In-Reply-To / References headers.** Do they survive a `content` write? Scripting doesn't expose them, so this needs checking from Sent-less evidence, such as the draft's source after autosave.
3. **Round-trip exactness.** Does Mail normalize whitespace or line endings on write? If so, the exact read-back check reports `unverified`. That is safe, but it makes editing unusable until it's adapted.
4. **Window identity.** Is `CFHash` of the window element stable across AX re-reads for the window's lifetime? This is believed true but untested here.
