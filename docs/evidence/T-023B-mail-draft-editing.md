# T-023B evidence: Mail draft editing by voice

**Date:** 2026-11-15 · **Branch:** `feature/mail-draft-editing` (uncommitted) · **Base:** `02b50b5` (main @ `c7327c7` + FlowText from PR #10, not yet merged) · **Design:** ADR 0010

> **Every result below is simulated.** These tests use fake Mail scripting and a fake Accessibility inspector, or `MockExecutor`. No test touched real Mail. The user chose "simulated only" for this milestone. The real-Mail path is implemented, compiles, and is **off by default** (`allowMailDraftEditing = false`). It has a gated live test that has **not been run**.

## Changed files
| Area | Files | Change |
|---|---|---|
| FlowCore | `FlowAction.swift` | `edit_text` action (deterministic only, `modelEmittable` excludes it) |
| FlowLLM | `IntentSchema.swift`, `IntentValidator.swift` | Schema omits `edit_text`; the validator rejects it |
| FlowRouting | `Rules.swift`, `IntentRouter.swift`, `ConversationContext.swift`, `Guard.swift`, `Text.swift` | `draftEdit` / `draftReview` rules, `PendingQuestion.textEdit`, punctuation helper |
| FlowPlanner | `Plan.swift`, `Executor.swift`, `PlanRunner.swift`, `TaskPlanner.swift`, `MockExecutor.swift`, **`DraftEditing.swift`** (new) | `.draftEdited` expectation and verification, `.textChoice` observation, spoken read-back, opener clauses, shared FlowText ↔ executor mapping, mock FlowText backend |
| FlowText | `EditCommand.swift`, `TextEditor.swift`, `TextEditingSession.swift`, **`AuthoredText.swift`** (new) | "undo that last change"; a new sentence after unpunctuated text gets ". "; undo anchoring at text edges; `isAnswer`; authored/quoted split |
| FlowMail | `MailDrafts.swift`, `JXAMailBackend.swift`, `MailTypes.swift` | Window identity and selection (no title-only matching), `draftDetails` / `setDraftContent` compare-and-set JXA ops, `editableText` / `replaceAuthored`, `MailError.draftChanged` |
| FlowExecutor | `MacPlanExecutor.swift`, **`MailDraftTextBackend.swift`** (new) | `edit_text` handling, `allowMailDraftEditing` (default off), unverified-write reporting |
| Other | `Package.swift`, `FlowBenchCLI/Benchmark.swift`, README, ADR 0010 | Dependencies: FlowRouting/FlowPlanner/FlowMail → FlowText |
| Tests | 6 new files, 4 updated fakes and rigs | See below |

## Acceptance sequence (simulated)
Run three ways: `DraftEditingIntegrationTests.acceptanceSequence` (real router, planner and `MacPlanExecutor` over fake Mail), `DraftEditingPlanTests` (MockExecutor), and `DraftEditingSpokenTests.acceptanceSequence` (scripted recognizer → coordinator → spoken feedback).

| Utterance | Result |
|---|---|
| "Find Sarah's email." | "Which Sarah? Sarah Chen, …; or Sarah Okafor, …" |
| "The first one." | Message selected |
| "Reply saying I can meet at 3:30." | One draft to sarah.chen@example.invalid, "Re: [FlowTest] Meeting tomorrow", body `I can meet at 3:30` |
| "Actually, change 3:30 to 4." | `edit_text("change 3:30 to 4.")`, body `I can meet at 4`; says "Changed “3:30” to “4”. The draft now says: “I can meet at 4”" |
| "Also say I'll send the details tonight." | Body `I can meet at 4. I'll send the details tonight.` |
| "What does the draft say?" | `request_review`; says "Here's the draft. It says: “I can meet at 4. I'll send the details tonight.”" |
| "Undo that last change." | Body `I can meet at 4`; says "Undone. …" |
| Throughout | One draft, same id, recipients, subject and `inReplyTo`; version increases on each edit; no Cc/Bcc; no `request_send` |

## Requirements → tests
| Requirement | Evidence (all simulated) |
|---|---|
| The seven brief commands | `DraftEditRoutingTests.briefCommandsBecomeEditText`, `DraftEditingIntegrationTests.theOtherBriefCommands`, `acceptanceSequence` |
| Deterministic routing, no model | `briefCommandsBecomeEditText` (model never called), `EditTextIsNotModelEmittableTests` |
| Context selects the draft; clarify when none | `editIsOneVerifiedStepBoundToTheCurrentDraft`, `withoutADraftFlowAsks`, `noDraftAsksInsteadOfEditing` |
| Read before, verify after | `replaceWritesVerifiesAndBumpsTheVersion`, `aWriteNotShownOnScreenIsUnverified`, `withoutAccessibilityAWriteIsUnverified`, `mailRewritingTheTextIsNotReportedAsDone`, `aWriteTheWindowDoesNotShowIsNeverReportedAsDone` |
| Detect external changes; never overwrite | `externalChangeBumpsTheVersionAndStaleWritesAreRefused`, `editAfterAnExternalChangeUsesTheLiveTextAndKeepsTheUsersWords`, `externalEditBetweenTurnsIsNotOverwritten`, `undoRefusesWhenTheUserRetypedTheEditedSpan` |
| Preserve recipients, Cc, subject, threading | `acceptanceSequence` (id, recipients, subject, `inReplyTo`), `replaceWritesVerifiesAndBumpsTheVersion`, `quotedOriginalIsKeptByteForByte` (both suites) |
| No duplicate drafts | `creates == 1` in every integration test; `creationWithTwoEquallyMatchingWindowsIsAnAmbiguityError` (a retry creates nothing); `aDraftThatIsGoneIsReportedNotRecreated` |
| Reject stale or ambiguous edits | `twoIdenticalDraftsAreNeverEditedByGuess`, `duplicateDraftsWithTheSameSubjectAreAmbiguousNotGuessed`, the stale-version tests |
| Duplicate-window fix (create, review, edit) | `ComposeSelectionTests` (5), `DuplicateWindowTests` (4), `windowIdentityTellsSameTitledDraftsApart` |
| Occurrence and preview questions in the shared context | `occurrenceAnswersGoBackToFlowText`, `previewAnswersGoBackToFlowText`, `duplicateWordAsksAndTheAnswerReachesFlowText`, `occurrenceQuestionPausesInTheSharedContext`, `whichOccurrenceIsAskedAloudAndAnsweredByVoice` |
| Stop/cancel | `stopDropsTheDraftQuestion`, `stopBeforeTheEditLandsChangesNothing` |
| Versioning invalidates approval; send disabled | `editInvalidatesAnEarlierReviewSoSendNeedsANewOne`; no `request_send` in the executor log |
| Spoken feedback | `DraftEditingSpokenTests` (2) |
| Editing off unless enabled | `editingIsOffByDefault` |

## Results
- `swift test` (full): **620 pass, 0 fail.** That is 566 before this milestone plus 54 new (12 executor integration, 20 FlowMail, 7 planner, 9 routing, 2 spoken, 2 validator, 2 gated live). The live suites are skipped without their environment flags.
- **Calendar, spoken-feedback, FlowText (41/41) and T-023A reply-draft suites all pass unchanged.**
- During development, one full run had `SpokenSessionAcceptanceTests.whichSarahIsSpokenAndAnsweredByVoice` fail once on its 3-second wait. It passed alone and in the next full run. It looks like a timing flake under load, but that isn't confirmed.

## Not verified (needs a live run)
To run it: `FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 FLOW_LIVE_EDIT=1 swift test --filter LiveDraftEditingTests`. It uses FlowTest messages only, never sends, and `TestDraftCleanup` closes only "FLOWTEST SAFE:" drafts.
1. Whether Mail keeps the quoted original, its formatting and the threading headers when a reply's `content` is set (ADR 0010, risks 1–2).
2. Whether the scripting read-back is exact after a write (risk 3). If not, edits report `unverified` and nothing is claimed.
3. `CFHash` window identity across re-reads (risk 4).
4. Whether the compose body's AX value and selected text are settable. `probeComposeBodyAccessibility` prints this; it's needed to decide whether to switch to the AX-edit alternative.

## Design corrections found while testing
1. **"Actually, change 3:30 to 4" was declined.** The planner split off "Actually" as its own clause and sent it to the model. Leading opener clauses are now dropped.
2. **"Remove the last sentence" was declined** as "Deleting isn't supported". The edit rule now runs before that rule (it still fires only with a draft, or asks).
3. **"Add Sarah to the meeting" would have become draft text.** Appends now need "add that…" or "also say…".
4. **Appended sentences lost their period** (clause splitting strips it) and ran together ("…at 4 I'll…"). The final mark is restored, and ". " is inserted after unpunctuated text.
5. **Undo after "4" → "4:15" at the end of the text** produced "3:30:15". Undo spans at the text edges are now anchored, so it refuses.
6. **Two same-subject drafts with the same recipients** made review fail outright. Scripting now breaks the tie by exact text, and stays ambiguous when the texts are equal.
