# T-025 evidence — Dictation and text-editing engine (FlowText)

**Date:** 2026-11-15 · **Branch:** `feature/text-editing` (uncommitted) · **Base:** `main` @ 3d82d4a · Design: ADR 0009
All tests use `SimulatedTextBackend`. Nothing touches macOS, and nothing is sent or deleted.

## Changed files
| File | Change |
|---|---|
| `Sources/FlowText/*` (new) | `TextModel`, `TextBackend` (+ `SimulatedTextBackend`), `EditCommand` (parser), `TextEditor` (pure planner), `TextEditingSession`, `RewriteCheck` (`FactCheck`, `RewriteGenerating`) |
| `Tests/FlowTextTests/TextEditingTests.swift` (new) | 41 tests |
| `Package.swift` | +6: `FlowText` target, product, test target (depends on FlowCore only) |
| FlowCore, FlowPlanner, FlowRouting, FlowMail, FlowAX, FlowApp, FlowExecutor, FlowSession, Calendar | **untouched**; no dependency on the spoken-feedback branch |

## Acceptance
"I can meet at 3:30 tomorrow." + "Change 3:30 to 4" → `applied`:
- Snapshot text `"I can meet at 4 tomorrow."`, version 1 → 2, changed span `"4"`.
- The `TextChange` sent to the backend had `baseVersion 1` and `expectedText` equal to the result, and the returned snapshot matched it exactly (verified).
- "Undo that change" → `"I can meet at 3:30 tomorrow."`, history empty. (`AcceptanceTests.changeVerifyAndUndo`)

## Requirements → tests
| # | Requirement | Evidence |
|---|---|---|
| 1 | Separate module | `FlowText`, depending only on FlowCore |
| 2 | Literal dictation | `dictationIsLiteralIncludingCommandWords` ("Delete the last sentence and send it to Sarah." and "Change 3:30 to 4." inserted verbatim), `embeddedStopInsideDictationIsText`, `sendSpokenInDictationIsNeverASend` |
| 3 | The six example requests | `ParserTests.parses` (all six, plus ordinals, "every", quotes, prepend, delete word, rewrites) |
| 4 | Deterministic, no Bonsai | Parser and editor are pure code; rewrites are the only model hook (`RewriteGenerating`), always previewed |
| 5 | Exact content preserved | `everyOtherCharacterIsPreserved` (curly quotes, apostrophes, hyphens, accents, emoji, em dash, "3:30 p.m.", "12th", phone numbers, emails, newlines), `appendKeepsTheUsersPunctuationAndAddsOnlyASpace`, `numbersAndNamesMatchOnTokenBoundariesOnly` |
| 6 | Duplicates ask | `duplicatePhraseAsksWhichOne`, `duplicateChoiceIsAnsweredByNumber`, `allOfThemReplacesEveryOccurrence`, `duplicateOptionsMarkWhichOccurrence`, `unrelatedCommandDropsAnOpenChoice` |
| 7 | Versions; refuse external overwrites | `staleTextIsNeverOverwritten` (user types during apply → refused, user's text intact), `textChangedWhileChoosingIsPlannedAgain`, `previewIsRefusedIfTextChangedMeanwhile`, `verificationFailureIsNotRecordedAsUndoable` |
| 8 | Targeted undo | `changeVerifyAndUndo`, `undoSurvivesUnrelatedExternalEdits`, `undoWithEditsOnBothSidesOfTheChange`, `undoRefusesIfTheEditedSpanChanged`, `undoWalksBackSeveralEditsInOrder` |
| 9 | Dictation vs stop/cancel/stop dictation | `stopDictationExitsAndCommandsWorkAgain`, `stopInterruptsDictationAndLaterWordsAreNotInserted`, `stopDuringAnInFlightDictationChunkCommitsItButNothingAfter`, `controlPhrases` |
| 10 | Preview before substantial rewrites | `rewriteIsPreviewedWithFactWarningsAndAppliedOnlyOnKeep` (warns "drops 3:30"), `discardLeavesTheTextAlone`, `substantialChangesNeedAPreview`, `withoutARewriterRewritesAreDeclined` |
| 11 | Simulated backends + unit tests | `SimulatedTextBackend` (external edits, delays, read-only, corruption); 41 tests |
| 12 | Interface for Track A | `TextBackend` (ADR 0009 §2) |
| 13 | Never send/delete | `sendAndDocumentDeletionAreNeverPerformed`, `deletingTheDocumentIsRefused`, `readOnlyFieldIsRefused` |

## Results
- `swift test --filter FlowTextTests`: **41/41 pass**, 3 repeated runs.
- `swift test` (full): **496 pass** (455 existing + 41 new), no failures.

## Design corrections found while testing
1. **Explicit replacements were being previewed.** Replacing most of a short text ("tomorrow and tomorrow") counted as "substantial". Per PRD D-011, targeted edits apply directly with undo; only rewrites and large deletions are previewed.
2. **Targeted undo failed after external edits on both sides of a change.** A single-region diff was replaced with context-anchored location: a unique match is required, with at least one unchanged neighbor on each side, so "4" → "4:15" next to the span still refuses.
3. **Fact check counted "3:30" as three facts** ("3", "30", "3:30"). Matches are now masked in priority order.
4. **Duplicate options were indistinguishable** on short texts. The occurrence is now bracketed in its context.

## Limitations
1. **Not connected to any real app.** Mail, AX, Messages and Notes backends are Track A work (ADR 0009 §2), and planner integration needs a decision (§3 Option A or B).
2. **Matching is literal.** "3:30" in the text won't match an ASR "330" (FlowRouting's colon confirmation handles that upstream). Number words ("three thirty") won't match digits.
3. **Parser phrasing is English and rule-based.** Unusual wording falls through as `notHandled`, which is safe.
4. **Sentence splitting uses `NLTokenizer`.** Abbreviations ("Dr. Smith") can split sentences unexpectedly; that's visible and undoable.
5. **Undo covers only Flow's edits, newest first**, up to 20, and there's no redo.
6. **In dictation, the single word "stop" or "cancel"** cannot be dictated literally (FlowCore control phrases win, as spec 02 §11 allows).
7. **No rewrite generator yet.** Rewrites are declined unless one is injected.
