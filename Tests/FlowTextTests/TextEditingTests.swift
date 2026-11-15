import FlowCore
@testable import FlowText
import Foundation
import Testing

let doc = TextDocumentID("mail-draft:d-1")

func session(_ text: String, rewriter: (any RewriteGenerating)? = nil) async -> (TextEditingSession, SimulatedTextBackend) {
    let backend = SimulatedTextBackend()
    await backend.create(doc, text: text)
    return (TextEditingSession(document: doc, backend: backend, rewriter: rewriter), backend)
}

func snapshot(_ text: String, version: Int = 1, caret: Int? = nil) -> TextSnapshot {
    TextSnapshot(document: doc, text: text, version: version, selection: caret.map { TextRange(location: $0, length: 0) })
}

func applied(_ o: EditOutcome) -> AppliedEdit? { if case .applied(let a) = o { a } else { nil } }

@Suite("Acceptance")
struct AcceptanceTests {
    @Test func changeVerifyAndUndo() async throws {
        let (s, backend) = await session("I can meet at 3:30 tomorrow.")
        let result = try #require(applied(await s.handle("Change 3:30 to 4")))
        // The expected snapshot is verified: exact text, new version.
        #expect(result.snapshot.text == "I can meet at 4 tomorrow.")
        #expect(result.snapshot.version == 2)
        #expect(result.changedText == "4")
        #expect(await backend.text(doc) == "I can meet at 4 tomorrow.")
        let change = try #require(await backend.applied.first)
        #expect(change.baseVersion == 1 && change.expectedText == "I can meet at 4 tomorrow.")

        guard case .undone(let undone) = await s.handle("Undo that change") else { Issue.record("not undone"); return }
        #expect(undone.snapshot.text == "I can meet at 3:30 tomorrow.")
        #expect(await backend.text(doc) == "I can meet at 3:30 tomorrow.")
        #expect(await s.history.isEmpty)
    }
}

@Suite("Parser: deterministic edit commands")
struct ParserTests {
    @Test(arguments: [
        ("Add that I'll be late.", EditOperation.append("I'll be late.")),
        ("Also say I'm available Friday.", .append("I'm available Friday.")),
        ("Change 3:30 to 4.", .replace(candidates: [(old: "3:30", new: "4")], .only)),
        ("Replace tomorrow with Wednesday.", .replace(candidates: [(old: "tomorrow", new: "Wednesday")], .only)),
        ("Remove the last sentence.", .delete(.lastSentence)),
        ("Undo that change.", .undo),
        ("Flow, add that I'll be late.", .append("I'll be late.")),
        ("change the second tomorrow to Friday", .replace(candidates: [(old: "tomorrow", new: "Friday")], .ordinal(2))),
        ("replace every Sam with Samuel", .replace(candidates: [(old: "Sam", new: "Samuel")], .all)),
        (#"replace "3:30 p.m." with "4 p.m.""#, .replace(candidates: [(old: "3:30 p.m.", new: "4 p.m.")], .only)),
        ("delete the word really", .delete(.phrase("really", .only))),
        ("scratch that", .undo),
        ("make it more formal", .rewrite(.formal)),
        ("start with Hi Sarah,", .prepend("Hi Sarah,")),
    ])
    func parses(utterance: String, expected: EditOperation) {
        #expect(EditCommandParser.parse(utterance) == .edit(expected))
    }

    @Test(arguments: [("stop", ControlCommand.stop), ("Flow, cancel.", .cancel), ("Flow, stop dictation", .stopDictation), ("never mind", .cancel)])
    func controlPhrases(utterance: String, control: ControlCommand) {
        #expect(EditCommandParser.parse(utterance) == .control(control))
    }

    @Test(arguments: ["delete the draft", "remove the whole email", "discard this message", "clear everything"])
    func deletingTheDocumentIsRefused(utterance: String) {
        guard case .refused = EditCommandParser.parse(utterance) else { Issue.record("\(utterance) not refused"); return }
    }

    @Test(arguments: ["send it", "open notes", "find Sarah's email", "what's on my calendar"])
    func nonEditsAreLeftForTheRouter(utterance: String) {
        #expect(EditCommandParser.parse(utterance) == .notAnEdit)
    }

    @Test func toInsideOperandsProducesEveryCandidateSplit() {
        guard case .edit(.replace(let c, _)) = EditCommandParser.parse("change go to the store to visit the store") else {
            Issue.record("no replace"); return
        }
        #expect(c.map(\.old) == ["go", "go to the store"])
    }
}

@Suite("Editor: matching, duplicates and exact content")
struct EditorTests {
    @Test func numbersAndNamesMatchOnTokenBoundariesOnly() {
        #expect(TextEditor.occurrences(of: "3", in: "Meet at 3:30 or 13 or 3.").count == 1)
        #expect(TextEditor.occurrences(of: "Sam", in: "Samantha and Sam").count == 1)
        #expect(TextEditor.occurrences(of: "tomorrow", in: "Tomorrow? Yes, tomorrow.").count == 2)
    }

    @Test func duplicatePhraseAsksWhichOne() {
        guard case .choose(let c) = TextEditor.plan(.replace(candidates: [(old: "tomorrow", new: "Wednesday")], .only),
                                                   on: snapshot("See you tomorrow. Tomorrow works.")) else {
            Issue.record("expected a choice"); return
        }
        #expect(c.options.count == 2)
        #expect(c.prompt.contains("appears 2 times"))
    }

    @Test func splitAmbiguityIsResolvedByTheText() {
        guard case .edit(let op) = EditCommandParser.parse("change go to the store to visit the shop") else { return }
        guard case .plan(let p) = TextEditor.plan(op, on: snapshot("I need to go to the store.")) else {
            Issue.record("not planned"); return
        }
        #expect(p.after == "I need to visit the shop.")
    }

    @Test func notFoundIsReported() {
        guard case .notFound(let why) = TextEditor.plan(.replace(candidates: [(old: "Friday", new: "Monday")], .only),
                                                        on: snapshot("See you Thursday.")) else { Issue.record("expected notFound"); return }
        #expect(why.contains("Friday"))
    }

    @Test(arguments: [
        ("Dear Ms. O'Brien-Smith, “Café Zoë” at 3:30 p.m. on the 12th — ok? 👍", "3:30 p.m.", "4 p.m.",
         "Dear Ms. O'Brien-Smith, “Café Zoë” at 4 p.m. on the 12th — ok? 👍"),
        ("Call +1 (555) 010-0199 or mail a.b@example.com.", "a.b@example.com", "c.d@example.org",
         "Call +1 (555) 010-0199 or mail c.d@example.org."),
        ("Line one.\nLine “two”.", "“two”", "“2”", "Line one.\nLine “2”."),
    ])
    func everyOtherCharacterIsPreserved(text: String, old: String, new: String, expected: String) {
        guard case .plan(let p) = TextEditor.plan(.replace(candidates: [(old: old, new: new)], .only), on: snapshot(text)) else {
            Issue.record("not planned"); return
        }
        #expect(p.after == expected)
    }

    @Test func appendKeepsTheUsersPunctuationAndAddsOnlyASpace() {
        guard case .plan(let p) = TextEditor.plan(.append("I'll be late."), on: snapshot("See you at 4.")) else { return }
        #expect(p.after == "See you at 4. I'll be late.")
        guard case .plan(let q) = TextEditor.plan(.append("Thanks!"), on: snapshot("")) else { return }
        #expect(q.after == "Thanks!")
    }

    @Test func deletionsAreTidyAndExact() {
        guard case .plan(let last) = TextEditor.plan(.delete(.lastSentence), on: snapshot("Hi Sarah. I can meet at 4. See you then!")) else { return }
        #expect(last.after == "Hi Sarah. I can meet at 4.")
        guard case .plan(let word) = TextEditor.plan(.delete(.phrase("really", .only)), on: snapshot("I really can't wait.")) else { return }
        #expect(word.after == "I can't wait.")
        guard case .plan(let lastWord) = TextEditor.plan(.delete(.lastWord), on: snapshot("See you tomorrow.")) else { return }
        #expect(lastWord.after == "See you.")
    }

    @Test func insertAtTheCaretAddsSpacesOnlyWhereNeeded() {
        guard case .plan(let p) = TextEditor.plan(.insert("really"), on: snapshot("I can meet.", caret: 5)) else { return }
        #expect(p.after == "I can really meet.")
    }

    @Test func substantialChangesNeedAPreview() {
        let long = String(repeating: "This is a sentence that goes on for a while. ", count: 3) + "Short end."
        guard case .plan(let p) = TextEditor.plan(.delete(.phrase(String(long.dropLast(11)), .only)), on: snapshot(long)) else { return }
        #expect(p.requiresPreview)
        guard case .plan(let small) = TextEditor.plan(.replace(candidates: [(old: "end", new: "finish")], .only), on: snapshot(long)) else { return }
        #expect(!small.requiresPreview)
    }
}

@Suite("Session: choices, staleness and undo")
struct SessionTests {
    @Test func duplicateChoiceIsAnsweredByNumber() async throws {
        let (s, backend) = await session("See you tomorrow. Tomorrow works.")
        guard case .choose = await s.handle("replace tomorrow with Wednesday") else { Issue.record("no choice"); return }
        #expect(await backend.applied.isEmpty)  // nothing changed while asking
        let a = try #require(applied(await s.handle("the second one")))
        #expect(a.snapshot.text == "See you tomorrow. Wednesday works.")
    }

    @Test func allOfThemReplacesEveryOccurrence() async throws {
        let (s, _) = await session("tomorrow and tomorrow")
        _ = await s.handle("change tomorrow to Friday")
        #expect(applied(await s.handle("all of them"))?.snapshot.text == "Friday and Friday")
    }

    @Test func textChangedWhileChoosingIsPlannedAgain() async throws {
        let (s, backend) = await session("See you tomorrow. Tomorrow works.")
        _ = await s.handle("replace tomorrow with Wednesday")
        await backend.externalEdit(doc, text: "Tomorrow works.")  // user edited: one occurrence left
        let a = try #require(applied(await s.handle("the second one")))
        #expect(a.snapshot.text == "Wednesday works.")
    }

    @Test func staleTextIsNeverOverwritten() async throws {
        let (s, backend) = await session("I can meet at 3:30 tomorrow.")
        await backend.setApplyDelay(.milliseconds(200))
        let edit = Task { await s.handle("change 3:30 to 4") }
        try await Task.sleep(for: .milliseconds(50))
        await backend.externalEdit(doc, text: "I can meet at 5 tomorrow.")  // the user typed meanwhile
        guard case .refused(let why) = await edit.value else { Issue.record("expected refusal"); return }
        #expect(why.contains("changed outside Flow"))
        #expect(await backend.text(doc) == "I can meet at 5 tomorrow.")  // user's text intact
        #expect(await s.history.isEmpty)
    }

    @Test func undoSurvivesUnrelatedExternalEdits() async throws {
        let (s, backend) = await session("I can meet at 3:30 tomorrow.")
        _ = await s.handle("change 3:30 to 4")
        await backend.externalEdit(doc, text: "Hi! I can meet at 4 tomorrow. Thanks")
        guard case .undone(let u) = await s.handle("undo") else { Issue.record("not undone"); return }
        #expect(u.snapshot.text == "Hi! I can meet at 3:30 tomorrow. Thanks")
    }

    @Test func undoRefusesIfTheEditedSpanChanged() async throws {
        let (s, backend) = await session("I can meet at 3:30 tomorrow.")
        _ = await s.handle("change 3:30 to 4")
        await backend.externalEdit(doc, text: "I can meet at 4:15 tomorrow.")
        guard case .refused(let why) = await s.handle("undo that") else { Issue.record("expected refusal"); return }
        #expect(why.contains("can't undo"))
        #expect(await backend.text(doc) == "I can meet at 4:15 tomorrow.")
    }

    @Test func undoWalksBackSeveralEditsInOrder() async throws {
        let (s, backend) = await session("A b c.")
        _ = await s.handle("change b to B")
        _ = await s.handle("add that Done.")
        _ = await s.handle("undo")
        #expect(await backend.text(doc) == "A B c.")
        _ = await s.handle("undo")
        #expect(await backend.text(doc) == "A b c.")
        #expect(await s.handle("undo") == .nothingToUndo)
    }

    @Test func verificationFailureIsNotRecordedAsUndoable() async throws {
        let (s, backend) = await session("I can meet at 3:30.")
        await backend.corruptNext()
        guard case .failed = await s.handle("change 3:30 to 4") else { Issue.record("expected failure"); return }
        #expect(await s.history.isEmpty)
    }

    @Test func readOnlyFieldIsRefused() async throws {
        let backend = SimulatedTextBackend()
        await backend.create(doc, text: "Read only.", editable: false)
        let s = TextEditingSession(document: doc, backend: backend)
        guard case .refused = await s.handle("change Read to Write") else { Issue.record("expected refusal"); return }
    }
}

@Suite("Dictation")
struct DictationTests {
    @Test func dictationIsLiteralIncludingCommandWords() async throws {
        let (s, backend) = await session("Notes:")
        #expect(await s.handle("start dictation") == .dictationStarted)
        _ = await s.handle("Delete the last sentence and send it to Sarah.")
        _ = await s.handle("Change 3:30 to 4.")
        #expect(await backend.text(doc) == "Notes: Delete the last sentence and send it to Sarah. Change 3:30 to 4.")
        #expect(await s.mode == .dictation)
    }

    @Test func stopDictationExitsAndCommandsWorkAgain() async throws {
        let (s, backend) = await session("")
        _ = await s.handle("start dictation")
        _ = await s.handle("I can meet at 3:30.")
        #expect(await s.handle("Flow, stop dictation") == .dictationEnded)
        _ = await s.handle("change 3:30 to 4")
        #expect(await backend.text(doc) == "I can meet at 4.")
    }

    @Test func stopInterruptsDictationAndLaterWordsAreNotInserted() async throws {
        let (s, backend) = await session("Start.")
        _ = await s.handle("start dictation")
        #expect(await s.handle("Flow, stop") == .cancelled)
        #expect(await s.mode == .command)
        #expect(await s.handle("and then some more words") == .notHandled)
        #expect(await backend.text(doc) == "Start.")
    }

    @Test func stopDuringAnInFlightDictationChunkCommitsItButNothingAfter() async throws {
        let (s, backend) = await session("A.")
        _ = await s.handle("start dictation")
        await backend.setApplyDelay(.milliseconds(150))
        let chunk = Task { await s.handle("B.") }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await s.handle("cancel") == .cancelled)
        #expect(await chunk.value == .cancelled)  // it was committed, and reported as interrupted
        #expect(await backend.text(doc) == "A. B.")
        #expect(await s.history.count == 1)  // ...and can be undone
        await backend.setApplyDelay(nil)
        #expect(await s.handle("C.") == .notHandled)  // not dictating anymore
    }

    @Test func embeddedStopInsideDictationIsText() async throws {
        let (s, backend) = await session("")
        _ = await s.handle("start dictation")
        _ = await s.handle("Please stop by at four.")
        #expect(await backend.text(doc) == "Please stop by at four.")
        #expect(await s.mode == .dictation)
    }

    @Test func sendSpokenInDictationIsNeverASend() async throws {
        let (s, backend) = await session("")
        _ = await s.handle("start dictation")
        _ = await s.handle("send it")
        #expect(await backend.text(doc) == "send it")
    }
}

/// Fake rewrite generator (stands in for Bonsai).
struct FakeRewriter: RewriteGenerating {
    let output: String
    func rewrite(_ text: String, style: RewriteStyle) async -> String? { output }
}

@Suite("Previews and rewrites")
struct PreviewTests {
    @Test func rewriteIsPreviewedWithFactWarningsAndAppliedOnlyOnKeep() async throws {
        let (s, backend) = await session("Hi Sarah, I can meet at 3:30 on Friday.",
                                         rewriter: FakeRewriter(output: "Dear Sarah, I would be glad to meet on Friday."))
        guard case .preview(let p) = await s.handle("make it more formal") else { Issue.record("no preview"); return }
        #expect(p.missingFacts.contains("3:30"))
        #expect(p.prompt.contains("It drops 3:30"))
        #expect(await backend.text(doc) == "Hi Sarah, I can meet at 3:30 on Friday.")  // nothing applied yet
        _ = await s.handle("keep it")
        #expect(await backend.text(doc) == "Dear Sarah, I would be glad to meet on Friday.")
        _ = await s.handle("undo")
        #expect(await backend.text(doc) == "Hi Sarah, I can meet at 3:30 on Friday.")
    }

    @Test func discardLeavesTheTextAlone() async throws {
        let (s, backend) = await session("Hi Sarah.", rewriter: FakeRewriter(output: "Hello there."))
        _ = await s.handle("rephrase it")
        #expect(await s.handle("discard it") == .discarded)
        #expect(await backend.text(doc) == "Hi Sarah.")
    }

    @Test func previewIsRefusedIfTextChangedMeanwhile() async throws {
        let (s, backend) = await session("Hi Sarah.", rewriter: FakeRewriter(output: "Hello there."))
        _ = await s.handle("rephrase it")
        await backend.externalEdit(doc, text: "Hi Sarah!")
        guard case .refused = await s.handle("keep it") else { Issue.record("expected refusal"); return }
        #expect(await backend.text(doc) == "Hi Sarah!")
    }

    @Test func withoutARewriterRewritesAreDeclined() async throws {
        let (s, _) = await session("Hi.")
        guard case .refused = await s.handle("make it shorter") else { Issue.record("expected refusal"); return }
    }

    @Test func factCheckFindsNamesTimesDatesNumbersAndLinks() {
        let f = FactCheck.facts(in: "Meet Priya at 3:30 p.m. on Friday the 12th, room 204, see https://example.com or a@b.co.")
        for expected in ["priya", "3:30p.m.", "friday", "12th", "204", "https://example.com", "a@b.co"] {
            #expect(f.contains(expected), "\(expected) missing from \(f)")
        }
    }
}

@Suite("Safety")
struct SafetyTests {
    @Test func sendAndDocumentDeletionAreNeverPerformed() async throws {
        let (s, backend) = await session("Draft text.")
        #expect(await s.handle("send it") == .notHandled)
        guard case .refused = await s.handle("delete the draft") else { Issue.record("expected refusal"); return }
        #expect(await backend.text(doc) == "Draft text.")
        #expect(await backend.applied.isEmpty)
    }

    @Test func unrelatedCommandDropsAnOpenChoice() async throws {
        let (s, backend) = await session("tomorrow and tomorrow")
        _ = await s.handle("change tomorrow to Friday")
        #expect(await s.handle("open notes") == .notHandled)
        #expect(await s.handle("the first one") == .notHandled)
        #expect(await backend.text(doc) == "tomorrow and tomorrow")
    }
}

@Suite("Regressions found while building")
struct RegressionTests {
    @Test func explicitReplacementIsATargetedEditNotAPreview() async throws {
        let (s, _) = await session("tomorrow and tomorrow")
        _ = await s.handle("change tomorrow to Friday")
        #expect(applied(await s.handle("both"))?.snapshot.text == "Friday and Friday")
    }

    @Test func duplicateOptionsMarkWhichOccurrence() {
        guard case .choose(let c) = TextEditor.plan(.delete(.phrase("tomorrow", .only)), on: snapshot("tomorrow and tomorrow")) else { return }
        #expect(c.options == ["1. …[tomorrow] and tomorrow…", "2. …tomorrow and [tomorrow]…"])
    }

    @Test func undoWithEditsOnBothSidesOfTheChange() async throws {
        let (s, backend) = await session("one two three")
        _ = await s.handle("change two to 2")
        await backend.externalEdit(doc, text: "zero one 2 three four")
        guard case .undone(let u) = await s.handle("undo") else { Issue.record("not undone"); return }
        #expect(u.snapshot.text == "zero one two three four")
    }

    @Test func factCheckCountsATimeOnce() {
        let (missing, _) = FactCheck.compare(original: "Meet at 3:30.", proposed: "Meet soon.")
        #expect(missing == ["3:30"])
    }
}
