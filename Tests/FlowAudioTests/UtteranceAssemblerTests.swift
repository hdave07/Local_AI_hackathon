import FlowAudio
import Testing

@Suite("Utterance assembly: partial vs final")
struct UtteranceAssemblerTests {
    let policy = EndpointPolicy(trailingSilence: 0.7, unconfirmedTailTimeout: 4.0, maxUtteranceDuration: 30)

    @Test func hypothesisAloneNeverFinalizes() {
        var a = UtteranceAssembler(policy: policy)
        #expect(a.ingest(.hypothesis("open notes"), at: 0) == [.partial(.init(confirmed: "", hypothesis: "open notes"))])
        #expect(a.phase == .hearing)
        #expect(a.tick(at: 1.0) == [])
        #expect(a.tick(at: 3.9) == [])
        // Unconfirmed tail times out as incomplete, never final.
        #expect(a.tick(at: 4.0) == [.incomplete(.init(confirmed: "", hypothesis: "open notes"))])
        #expect(a.phase == .idle)
    }

    @Test func confirmedFinalizesAfterTrailingSilence() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.hypothesis("open"), at: 0)
        _ = a.ingest(.hypothesis("open notes"), at: 0.3)
        #expect(a.ingest(.confirmed("Open Notes.", language: "en"), at: 0.6)
            == [.partial(.init(confirmed: "Open Notes.", hypothesis: ""))])
        #expect(a.tick(at: 1.2) == [])  // 0.6 s quiet < 0.7 s
        #expect(a.tick(at: 1.3) == [.final(text: "Open Notes.", language: "en")])
        #expect(a.phase == .idle)
        #expect(a.tick(at: 5) == [])
    }

    @Test func pendingHypothesisBlocksFinalization() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.confirmed("Open", language: nil), at: 0)
        _ = a.ingest(.hypothesis("notes"), at: 0.1)
        #expect(a.tick(at: 2.0) == [])  // "notes" not yet stable
        _ = a.ingest(.confirmed("notes.", language: nil), at: 2.1)
        #expect(a.tick(at: 2.9) == [.final(text: "Open notes.", language: nil)])
    }

    @Test func partialStableTextWithUnconfirmedTailIsIncomplete() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.confirmed("Reply to Sarah", language: nil), at: 0)
        _ = a.ingest(.hypothesis("that I can meet"), at: 0.2)
        // Never route a truncated command built from stable text alone.
        #expect(a.tick(at: 4.2) == [.incomplete(.init(confirmed: "Reply to Sarah", hypothesis: "that I can meet"))])
    }

    @Test func activeSpeechDefersFinalization() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.voiceActivity(.speechStarted), at: 0)
        _ = a.ingest(.confirmed("Open", language: nil), at: 0.2)
        #expect(a.tick(at: 2.0) == [])  // VAD still says speech
        _ = a.ingest(.voiceActivity(.speechEnded), at: 2.1)
        #expect(a.tick(at: 2.5) == [])
        #expect(a.tick(at: 2.9) == [.final(text: "Open", language: nil)])
    }

    @Test func multipleUtterancesInOneStream() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.confirmed("Open Notes.", language: nil), at: 0)
        #expect(a.tick(at: 1) == [.final(text: "Open Notes.", language: nil)])
        _ = a.ingest(.confirmed("Scroll down.", language: nil), at: 3)
        #expect(a.tick(at: 4) == [.final(text: "Scroll down.", language: nil)])
    }

    @Test func cumulativeEngineTextIsNotDuplicated() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.confirmed("Open", language: nil), at: 0)
        _ = a.ingest(.confirmed("Open Notes.", language: nil), at: 0.2)
        #expect(a.confirmed == "Open Notes.")
        #expect(a.tick(at: 1) == [.final(text: "Open Notes.", language: nil)])
        // Next utterance reported cumulatively with the previous one as prefix.
        _ = a.ingest(.confirmed("Open Notes. Scroll down.", language: nil), at: 2)
        #expect(a.confirmed == "Scroll down.")
    }

    @Test func whitespaceIsNormalizedAndEmptyIgnored() {
        var a = UtteranceAssembler(policy: policy)
        #expect(a.ingest(.confirmed("   ", language: nil), at: 0) == [])
        #expect(a.ingest(.hypothesis(""), at: 0) == [])
        #expect(a.phase == .idle)
        _ = a.ingest(.confirmed("  open \n notes ", language: nil), at: 0.1)
        #expect(a.confirmed == "open notes")
    }

    @Test func retractedHypothesisReturnsToIdleSilently() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.hypothesis("uh"), at: 0)
        _ = a.ingest(.hypothesis(""), at: 0.2)
        #expect(a.tick(at: 1.0) == [])
        #expect(a.phase == .idle)
    }

    @Test func unchangedHypothesisDoesNotPostponeTimeout() {
        var a = UtteranceAssembler(policy: policy)
        _ = a.ingest(.hypothesis("open notes"), at: 0)
        for t in stride(from: 0.5, through: 3.5, by: 0.5) { _ = a.ingest(.hypothesis("open notes"), at: t) }
        #expect(a.tick(at: 4.0) == [.incomplete(.init(confirmed: "", hypothesis: "open notes"))])
    }

    @Test func maxDurationCapsContinuousSpeech() {
        var a = UtteranceAssembler(policy: EndpointPolicy(trailingSilence: 0.7, unconfirmedTailTimeout: 4, maxUtteranceDuration: 10))
        _ = a.ingest(.voiceActivity(.speechStarted), at: 0)
        _ = a.ingest(.confirmed("blah", language: nil), at: 0.5)
        #expect(a.tick(at: 9) == [])
        #expect(a.tick(at: 10.5) == [.final(text: "blah", language: nil)])
    }

    @Test func finishFlushesStableTextOnly() {
        var stable = UtteranceAssembler(policy: policy)
        _ = stable.ingest(.confirmed("Open Notes.", language: nil), at: 0)
        #expect(stable.finish() == [.final(text: "Open Notes.", language: nil)])

        var pending = UtteranceAssembler(policy: policy)
        _ = pending.ingest(.hypothesis("open notes"), at: 0)
        #expect(pending.finish() == [.incomplete(.init(confirmed: "", hypothesis: "open notes"))])

        var empty = UtteranceAssembler(policy: policy)
        #expect(empty.finish() == [])
    }
}

@Suite("End of segment")
struct EndOfSegmentTests {
    @Test func finalizesStableTextImmediately() {
        var a = UtteranceAssembler()
        _ = a.ingest(.hypothesis("open notes"), at: 0)
        _ = a.ingest(.confirmed("Open notes.", language: "en"), at: 1)
        #expect(a.ingest(.endOfSegment, at: 1) == [.final(text: "Open notes.", language: "en")])
    }

    @Test func leftoverHypothesisIsIncompleteNotFinal() {
        var a = UtteranceAssembler()
        _ = a.ingest(.hypothesis("open notes"), at: 0)
        #expect(a.ingest(.endOfSegment, at: 1) == [.incomplete(.init(confirmed: "", hypothesis: "open notes"))])
    }

    @Test func idleSegmentIsSilent() {
        var a = UtteranceAssembler()
        #expect(a.ingest(.endOfSegment, at: 1) == [])
    }

    @Test func nextUtterancesSpeechStateSurvives() {
        var a = UtteranceAssembler()
        _ = a.ingest(.confirmed("open notes", language: nil), at: 0)
        _ = a.ingest(.voiceActivity(.speechStarted), at: 0.5)  // next utterance begins
        _ = a.ingest(.endOfSegment, at: 0.6)
        #expect(a.speechActive)
    }
}

@Suite("Utterance segmenter")
struct UtteranceSegmenterTests {
    // 0.1 s chunks; threshold 0.3 on a 0–1 level scale.
    func make(_ policy: UtteranceSegmenter.Policy = .init(hold: 0.3, maxSegment: 30, maxIdle: 20)) -> UtteranceSegmenter {
        UtteranceSegmenter(vad: EnergyVoiceActivityDetector(threshold: 0.3, attack: 0.05, release: 0.4), policy: policy)
    }

    @Test func cutsAfterSpeechEndsPlusHold() {
        var s = make()
        #expect(s.process(level: 0.8, duration: 0.1) == .init(activity: .speechStarted, cut: false))
        for _ in 0..<5 { #expect(!s.process(level: 0.8, duration: 0.1).cut) }
        var cutAt: Int?
        var endedAt: Int?
        for i in 1...20 {
            let step = s.process(level: 0.05, duration: 0.1)
            if step.activity == .speechEnded { endedAt = i }
            if step.cut { cutAt = i; break }
        }
        #expect(endedAt == 4)  // 0.4 s release
        #expect(cutAt == 7)  // + 0.3 s hold
    }

    @Test func resumedSpeechCancelsPendingCut() {
        var s = make()
        _ = s.process(level: 0.8, duration: 0.1)
        for _ in 0..<5 { _ = s.process(level: 0.05, duration: 0.1) }  // ended, hold running
        #expect(s.process(level: 0.8, duration: 0.1).activity == .speechStarted)
        for _ in 0..<3 { #expect(!s.process(level: 0.8, duration: 0.1).cut) }
    }

    @Test func silenceAloneOnlyRecyclesAtMaxIdle() {
        var s = make(.init(hold: 0.3, maxSegment: 30, maxIdle: 2))
        for _ in 0..<19 { #expect(!s.process(level: 0.01, duration: 0.1).cut) }
        #expect(s.process(level: 0.01, duration: 0.1).cut)
    }

    @Test func longSpeechIsForceCutAndContinues() {
        var s = make(.init(hold: 0.3, maxSegment: 1.0, maxIdle: 20))
        var cuts = 0
        for _ in 0..<25 where s.process(level: 0.8, duration: 0.1).cut { cuts += 1 }
        #expect(cuts == 2)
        #expect(s.vad.isSpeech)
    }
}

@Suite("Energy VAD")
struct EnergyVADTests {
    let loud = [Float](repeating: 0.2, count: 1600)  // 0.1 s
    let quiet = [Float](repeating: 0.001, count: 1600)

    @Test func detectsSpeechStartAndEndWithHysteresis() {
        var vad = EnergyVoiceActivityDetector(threshold: 0.02, attack: 0.05, release: 0.3)
        #expect(vad.process(quiet) == nil)
        #expect(vad.process(loud) == .speechStarted)
        #expect(vad.process(loud) == nil)
        #expect(vad.process(quiet) == nil)  // 0.1 s
        #expect(vad.process(quiet) == nil)  // 0.2 s
        #expect(vad.process(quiet) == .speechEnded)  // 0.3 s
        #expect(!vad.isSpeech)
    }

    @Test func briefDipDoesNotEndSpeech() {
        var vad = EnergyVoiceActivityDetector(threshold: 0.02, attack: 0.05, release: 0.3)
        _ = vad.process(loud)
        _ = vad.process(quiet)
        #expect(vad.process(loud) == nil)
        #expect(vad.isSpeech)
    }

    @Test func emptyChunkIsIgnored() {
        var vad = EnergyVoiceActivityDetector(threshold: 0.02)
        #expect(vad.process([]) == nil)
        #expect(EnergyVoiceActivityDetector.rms([]) == 0)
    }
}
