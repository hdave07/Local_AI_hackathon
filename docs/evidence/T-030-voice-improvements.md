# T-030 evidence — Voice-to-intent reliability (Track B, Phase 2)

**Date:** 2026-11-14 · **Branch:** `feature/voice-improvements` (uncommitted) · **Machine:** Apple M5, 16 GB, macOS 26.6
**Stack:** Argmax Pro 3.1.8 `parakeet-v2_476MB` → `FlowAudio` → new `FlowRouting` → Bonsai 2 **2B** (`ternary-bonsai-2-2b-mlx`) via LM Studio. Nothing is executed.

## Method and honesty notes

- **Frozen evaluation.** `fixtures/heldout-benchmark.json` (31 intent + 15 ambiguous) and `fixtures/context-benchmark.json` (18 cases with prior task state, including negatives) were written **before** any routing code. Their SHA-256 hashes and the base commit are in `T-030/fixture-hashes-at-baseline.txt`. The fixture files are unchanged at the end (hashes re-checked).
- **Tuning data.** Rules were designed against the original T-002 fixtures (`bonsai-benchmark.json`) and the spec. I did not read held-out failure details before the first held-out run.
- **Caveat: same author.** I wrote the held-out phrasings and the rules, so text held-out results are **optimistic**. The stronger generalization evidence is the **ASR evaluation with unseen voices**: real Argmax transcripts whose errors I did not write.
- **Contamination is labelled.** ASR robustness fixes were derived from the first five voices' transcripts (held-out included). They were then validated on five **different** voices. Five bugs found *in* that validation were fixed afterwards; those fixes are **unit-tested only, not validated on unseen data**.
- Text benchmarks: 3 runs each, temperature 0, deterministic (100% identical across runs). ASR runs: 1 transcription per utterance × voice.
- Speech is synthetic (macOS `say`, 10 English voices). It is not a substitute for real users, or for users with speech impairments.

## 1. Text benchmark: baseline vs final

| Set (cases × 3 runs) | Baseline: Bonsai V1 alone | Bonsai V2 alone | **Final: router + V2** |
|---|---|---|---|
| Tuned intent (30) | 63/90 (70%) | 72/90 (80%) | **90/90 (100%)** |
| Tuned ambiguous (15) | 15/45 (33%) | 18/45 (40%) | **45/45 (100%)** |
| **Held-out intent (31)** | 57/93 (61%) | 72/93 (77%) | **93/93 (100%)** |
| **Held-out ambiguous (15)** | 9/45 (20%) | 12/45 (27%) | **45/45 (100%)** |
| Context (18) | 9/54 (17%) | 21/54 (39%) | **54/54 (100%)** |
| Unsafe guesses* tuned / held-out / context | 33 / 24 / 24 | 21 / 18 / 18 | **0 / 0 / 0** |
| Clarification where acceptable (tuned / held-out / context) | 0% / 0% / 0% | 13% / 7% / 60% | **67% / 73% / 80%** |
| Over-asking (clarified a definite command) | 0 / 3 / 0 | 0 / 3 / 9 | **0 / 0 / 0** |
| Email search (tuned 4 + held-out 4) × 3 | 12/24 | 24/24 | **24/24** |
| Draft content preserved (tuned 4 + held-out 4) × 3 | 21/24 | 21/24 | **24/24** |

\* Unsafe guess = a validated action outside the case's accept set (wrong app/recipient/time/content, or an action where a question was required).
Sources: `T-030/baseline`, `T-030/final-bonsai-v2-only`, `T-030/final-router-v2`.

**Routes (final, held-out):** fast path 67%, clarify 20%, guarded 9%, context 2%, model 2%. Most commands no longer reach Bonsai.

## 2. Real ASR transcripts (the generalization evidence)

Each fixture utterance was spoken by `say`, streamed through the real Argmax segmented pipeline, and its first final transcript was routed. `T-030/speech*`, `T-030/final-asr-routing`, `T-030/validation-old-vs-new`.

**ASR quality** (109 utterances per voice, natural pacing): no utterance missed or split.

| Voices | Exact transcript | Mean WER |
|---|---|---|
| Tuning: Samantha, Daniel, Karen, Moira, Aman | 71–84% | 0.06–0.17 |
| Validation: Tessa, Rishi, Reed, Flo, Shelley | 62–77% | 0.09–0.19 |

**Routing on unseen-voice transcripts** (validation voices; rules never saw these transcripts):

| Set (× 5 voices) | Old: Bonsai V1 | **New: router + V2** (as validated) | New after post-validation fixes† |
|---|---|---|---|
| Tuned | 111/225 (49%), 61 unsafe | **201/225 (89%), 8 unsafe** | 201/225 (89%), 8 unsafe |
| Held-out | 97/230 (42%), 57 unsafe | **189/230 (82%), 17 unsafe** | 191/230 (83%), 13 unsafe |
| Context | 15/90 (17%), 51 unsafe | **79/90 (88%), 2 unsafe** | 79/90 (88%), 1 unsafe |

† Post-validation fixes were derived from these transcripts, so this column is not independent.

**Regressions on unseen voices (old passed → new fails): 5 of 545.**
- 3 are now questions instead of lucky guesses: "Put male and camonda side by side" (Bonsai guessed Calendar), and "Write *the* Alex and ask…" ×2.
- 1 copies spoken number words: "Change three to three thirty" → `replace "three" → "three thirty"`.
- 1 is an ASR word split: "ten AM to morrow".

**Remaining unsafe results are mostly ASR content errors copied faithfully.** Examples: "Sera"/"Sira"/"Serah" for Sarah, "Donna" for Dana, "E"/"ye" for Lee, "pre-assaying"/"previous" for Priya, "C U soon", "flag confirmation". Routing cannot detect a misheard name. These need ASR contact vocabulary (see limitations) and the draft review step, which already exists before any send.

**Tuning voices before → after ASR fixes** (contaminated; shows the fixes work): tuned 207 → 213/225, held-out 193 → 204/230, context 72 → 76/90; unsafe 7 / 22 / 6 → 1 / 9 / 0; **0 regressions**.

## 3. What changed

### `FlowRouting` (new Track B module; depends on FlowCore + FlowLLM only)
Stage order:
1. stop/cancel (FlowCore `DeterministicRouter`, unchanged);
2. answer to a pending question;
3. decline actions that don't exist (close/quit/delete);
4. references resolved against context;
5. deterministic fast path;
6. Bonsai + guards.

- **Fast path:**
  - apps (open/launch/switch to/go to/bring up/show);
  - tiling (side by side, left/right, "and" heard as "end");
  - move/maximize/center/resize with explicit windows;
  - scroll;
  - send/review ("click send" → send-with-confirmation);
  - email search vs calendar decided by explicit nouns;
  - drafts with verbatim recipient and content (including "ask if…", "tell X …", `:`/`,`/`.` connectors, a final `?`/`!` kept); "reply to all" asks;
  - edits (type/replace) and click/focus.
  All patterns match the **whole** utterance; embedded commands fall through to Bonsai.
- **Task context (`ConversationContext`):** active app, ≤3 recent people, open message, draft flag, last edited text, pending question, 10 min TTL. References resolve only to a **unique** candidate; otherwise the router asks (e.g. "Did you mean Sarah or Sam?"). Explicit names always override context.
- **Clarification with follow-up:** questions carry a `PendingQuestion`. The next utterance can answer by name, number ("the first one"), position or yes/no. Any other command, or stop/cancel, drops the question.
- **Guards on model output:**
  - every slot (app, window, person, query, time, content, label, edited text) must be grounded in the utterance or the context;
  - size/position/scroll words must be spoken;
  - send/review need their verb;
  - mail-only wording can't become a calendar answer, and vice versa;
  - calendar answers need a question cue and a time word, and must keep every spoken time word;
  - search needs a find/read verb;
  - recipients must look like names (no pronouns or mail nouns);
  - pronouns in slots are unresolved references.
  Empty-slot validator rejections become targeted questions.
- **ASR robustness:** "2 p.m." → "2 pm", "2.30 p.m." → "2:30 pm"; "male" = Mail only in app positions. A colon-less time ("330", "3.45") in a content or calendar slot becomes **"Did you mean 3:30? Say yes, or no to keep it as heard"** rather than a guess.

### FlowLLM (Track B)
- **Prompt V2** (`IntentSchema.systemPrompt`; V1 and V3 kept for A/B), adding explicit mail/calendar/draft rules, copy-exactly, clarify bare references, and example values that don't recur elsewhere.
- Injectable `systemPrompt`, and public `ClassificationTrace` initializers.

### FlowAudio / FlowArgmax (Track B)
- `UtteranceSegmenter` default hold **0.3 → 0.6 s** (section 5).
- `VoicePipeline(onControl:)` hook, so stop/cancel also clears the router's pending question.
- `routedBy` is now derived from the intent's source, so fast-path answers aren't reported as Bonsai.
- `ArgmaxTranscriber.setInput/setSegmentPolicy`, and an `inverseTextNormalization` setting.

### Harnesses
- `flow-bench`: `--pipeline bonsai|router`, `--prompt v1|v2|v3`, multiple fixture files, context, route and latency stats, unsafe and clarification metrics.
- New `flow-speech-eval` (Argmax-gated): synthesize → stream → WER, missed/split, ASR fixture files; `--pause-ms`, `--hold`, `--itn`, `--min-words`; timeouts on `say` and transcription.
- `flow-voice` uses the router by default (`--no-router` to compare).

### FlowAX compatibility (after Track A's PR #3)
- Click/focus labels are passed through as spoken; FlowAX parses articles, ordinals and role words.
- Numbered-overlay phrases are recognized deterministically (stage `overlay`) and declined until a shared FlowCore action exists.
- Consequential click labels (send → `request_send`; delete/discard/trash → declined), including from model output.
- Re-ran the final text benchmark after these changes: still 100% on all three sets, 0 unsafe.

### FlowCore
- **No changes.** The shared `TaskContext` and structured clarification are **proposed** in `docs/adr/0004-task-context-and-clarification.md` for Track A.

## 4. Prompt A/B (Bonsai alone, tuned set; `T-030/prompt-ab`)

| Prompt | Intent | Ambiguous | Email search | Unsafe | Model call p50 (2 interleaved runs) |
|---|---|---|---|---|---|
| V1 (T-011) | 21/30 | 5/15 | 2/4 | 11 | 447 / 460 ms |
| **V2** | **24/30** | **6/15** | **4/4** | **7** | **338 / 350 ms** |
| V3 (V1 + 3 rules) | 22/30 | 3/15 | 2/4 | 10 | 538 ms (1 run) |

- **V2 regressions vs V1** (Bonsai alone): "email sarah" (now opens Mail; the router's fast path handles it), "do the usual" (now rejected instead of declined). Live, V2 also dropped "four" from "anything at four tomorrow"; the new time-completeness guard catches that.
- **Latency:** V2's tail is heavier. Model-call p95 was 1.25–1.6 s in the final runs, against ~0.4–0.6 s for V1. One isolated 1.2 s p50 run right after a build was not reproducible.
- **8 GB note:** V2 is ~15 lines longer than V1. Since the router answers ~70% of commands without the model, the model is called far less often than before. 2B on 8 GB was **not re-measured here** (this Mac has 16 GB). T-011 measured V1 at 2.6–3.5 s on 8 GB.

## 5. Speech segmentation (`T-030/segmentation-*`)

Silence inserted at the middle word boundary of 54 utterances (≥4 words) × Samantha + Daniel = 108 per cell.

| Mid-sentence pause | Split, hold 0.3 s | Split, hold 0.6 s |
|---|---|---|
| 300 ms | 0% | 0% |
| 500 ms | 0% | 0% |
| 700 ms | **30%** | 0% |
| 900 ms | **100%** | 0% |
| 1100 ms | — | **98%** |
| 1300 ms | — | **100%** |

- **Decision:** hold 0.6 s. Exact-transcript rate was unchanged (68–70% at all pauses ≤ 900 ms).
- **Cost (live test):** end of speech → final text went from 0.37 s to **0.67 s** after VAD speech-end.
- **Limit:** pauses of ~1 s or more still split commands.
- **No misses:** zero utterances missed in any condition.

## 6. Latency (final, warm, this Mac)

| Path | p50 | p95 |
|---|---|---|
| Fast path / context / deterministic clarification | 0.1–0.2 ms | ≤ 0.2 ms |
| Commands reaching Bonsai V2 | ~300–350 ms | ~1.25–1.6 s |
| All commands, text held-out | 0.1 ms | 352 ms |
| All commands, ASR transcripts | 0.2 ms | 1.5–1.7 s |
| End of speech → final transcript (hold 0.6 s) | ~0.67 s after VAD end | — |

Model warm-up after idle was 4.4 s once (LM Studio reload), and cold load was ~5 s (T-002).

## 7. Investigations and findings

- **Argmax ITN has no effect with Parakeet.** `inverseTextNormalization: true` gave byte-identical transcripts, so it is likely Qwen3-only. The colon-less times ("330") therefore have to be handled downstream, which the confirmation question does.
- **Harness hang (fixed):** the first segmentation run stalled for ~55 min. The cause was macOS `say` hanging on its speech-synthesis XPC service (0.3 s CPU), not Argmax. A block-buffered log hid where it was. `flow-speech-eval` now has a 20 s `say` deadline with retries, a 60 s per-transcription watchdog, and line-buffered output. The rerun recorded 0 timeouts over 1,080 transcriptions.
- **Earlier live misrecognition** ("Then uncles, I may uh talk and window"): not reproducible with synthetic speech. Input-device logging remains a recommended next step.

## 8. Tests

- `swift test` (this branch): **211 pass**: FlowWindow 48, FlowRouting 58 (new), FlowLLM 39, FlowCore 6, FlowBench 5, FlowAudio 47, FlowArgmax 8.
- **Against current `main` (5a4f285, Track A FlowAX):** changes applied in a scratch worktree build cleanly; **270 tests pass** including FlowAX 59. A temporary cross-track test confirmed router output bridges correctly through `NavCommand(FlowAction)` (ordinal and role preserved; send/delete/overlay never become raw clicks). Details: ADR 0004, "Response to Track A ADR 0003".
- Live: LM Studio 5/5; live Argmax 2/2 (final 0.67 s after speech end; spoken "Open Notes" file → `activate_app Notes`).

## 9. Limitations and open items

1. **Misheard names and content.** Add Argmax custom vocabulary from contacts (Parakeet-only; needs `canary-1b-v2_474MB` or `parakeet-tdt_ctc-110m`). Not wired yet. The draft review before send is the current safeguard.
2. **Pauses ≥ ~1 s split commands.** Recommended: an adaptive hold that waits longer when the live hypothesis ends in a connector ("that", "to", "and", "saying"). This uses the hypothesis for *timing only*, never for routing.
3. **Number words** ("three thirty") are copied as spoken; an exact-text replace of "three" will fail visibly if the draft has "3".
4. **Context comes from proposed intents**, not executor-verified state, until Track A adopts ADR 0003.
5. **Not measured:** 2B latency on an 8 GB Mac with prompt V2; real (non-synthetic) speakers; speakers with speech impairments; Bonsai 4B (not installed).
6. **Rule maintenance:** the fast path is a set of regular expressions. New phrasings that miss it fall back to Bonsai + guards (safe, but slower and less accurate).

## Reproduce

```
swift test
swift run flow-bench --pipeline router --prompt v2 --runs 3 \
  --fixtures fixtures/bonsai-benchmark.json --fixtures fixtures/heldout-benchmark.json \
  --fixtures fixtures/context-benchmark.json --out /tmp/final
set -a; . ./.env; set +a
swift run flow-speech-eval --fixtures fixtures/heldout-benchmark.json --voices Tessa,Rishi --out /tmp/asr
swift run flow-speech-eval --fixtures fixtures/heldout-benchmark.json --voices Samantha \
  --pause-ms 500,900 --min-words 4 --hold 0.6 --out /tmp/seg
scripts/flow_voice.sh --once           # microphone → router → mock consumer
```
