# T-002 evidence — Bonsai 2 + LM Studio benchmark

**Date:** 2026-11-14 · **Machine:** Apple M5 (Mac17,3), 16 GB RAM, macOS 26.6 · **Runtime:** LM Studio, `ternary-bonsai-2-2b-mlx` (1.21 GB, ctx 8192, parallel 4)
**Harness:** `swift run flow-bench --runs 3 --out docs/evidence/T-002`. Fixtures: `fixtures/bonsai-benchmark.json` (30 intent, 15 ambiguous, 10 malformed; synthetic).
Requests: `temperature 0`, `response_format json_schema strict`, the T-011 system prompt (unchanged).

## Headline results (final, deterministic schema order)

| Metric | Result |
|---|---|
| Intent accuracy (30 × 3) | **63/90 (70%)**, target ≥ 95%: **not met** |
| Ambiguous handled acceptably (15 × 3) | 15/45 (33%); `clarification` emitted **0/45**; unsafe guesses 12 |
| Email search (4 × 3) | 6/12 (50%) |
| Draft content preserved (4 × 3) | 9/12 (75%); every `create_draft` produced kept the content; the miss is I21 routed to `read_message` |
| JSON-schema conformance (first attempt) | parseable 100%, exact fields 100%, passed strict validator 82% |
| Malformed outputs rejected with the expected error | **10/10** (also a unit test) |
| Repeatability | **100%**: identical results across 3 runs and 3 separate processes |
| Warm latency per call | p50 446–477 ms, p95 507–544 ms (n=135 per run) |
| Cold first request (model unloaded → JIT load) | **4.8 s / 5.7 s** (two trials); next warm call 432–450 ms |

Full rows: `T-002/results.csv`; summary: `T-002/summary.md`.

## Bug found and fixed: field order varied per process

Before the fix, two identical benchmark runs gave **64% and 39%** intent accuracy (draft content 75% vs 0%); see `T-002/baseline-random-order-{1,2}`.
**Cause:** the JSON schema was a Swift `Dictionary`. Its key order is randomized per process, and LM Studio's constrained decoder emits fields in `properties` order. One launch generated `summary, target, kind, detail, action`, choosing `target` *before* `action` and leaving it empty. This also explains T-011's "output varies across runs at temperature 0".
**Fix:** `OrderedJSON` (FlowLLM) serializes the request with `properties` in `IntentSchema.fields` order. Covered by tests: wire order, byte-identical requests, escaping.

| Field order | Intent | Ambiguous OK | Unsafe ambiguous | Validator-accepted |
|---|---|---|---|---|
| random, run 1 | 58/90 | 13/45 | 12 | 73% |
| random, run 2 | 35/90 | 3/45 | 9 | 50% |
| **kind, action, target, detail, summary (chosen)** | **63/90** | **15/45** | **12** | **82%** |
| action, target, detail, summary, kind | 66/90 | 21/45 | 21 | 93% |

**Why kind-first and not action-first:** action-first scores +3 on intent, but nearly doubles unsafe ambiguous guesses (12 → 21) and introduces a wrong content edit (I19 `replace "tomorrow" → "wednesday"`). PRD principle 1 ranks no silent consequential errors above effort, so kind-first is the default. This is reversible in one line (`IntentSchema.fields`) if the team prefers otherwise.

## Remaining failure classes (final run)

1. **Email search → calendar** (I24 `find sarah's email about tomorrow` → `query_calendar "tomorrow 4 pm"`), **compose → search** (I21 `email john saying…` → `read_message`).
2. **Few-shot value leakage:** `tomorrow 4 pm` appears in unrelated queries (I24, I29 "friday afternoon"); `Mail, Calendar` in A09 "put them side by side". This is a *silent factual error* risk for calendar answers.
3. **Enum confusion:** "maximize" → `resize_window` (I09), "top" → `up` (I13), "smaller" → `narrower` + wrong window (I11).
4. **Wrong-field or empty arguments** (validator rejects, safe but useless): I26 search query empty, A13/A15.
5. **No clarification ever:** the model guesses (A01 "open it" → Safari) or emits an action with empty arguments.
6. I17 `type hello everyone` → `activate_app Safari`.

No result produced `request_send` for anything except "send it" in the final order. Every validated intent goes through the executor's risk and confirmation rules regardless.

## Model comparison (2B vs 4B)

**Not run.** Bonsai 2 **4B is not installed** on this machine; LM Studio has 2B and 27B (8.61 GB). Comparing 4B needs a ~2–3 GB download (`lms get`), and only with the team's approval. 27B was not attempted: it is outside the requested comparison and would take more than half of 16 GB of RAM next to the ASR model.

## Recommendations (not implemented: each needs this benchmark as a regression gate)

1. **Deterministic fast path first** (spec principle 5): a small grammar for `open/launch/switch to <app>`, `scroll up/down/top/bottom`, `send it`, `maximize/left half/right half <app>`, `tile A and B`. Covers I01–I13 and I30 with ~0 ms latency, and leaves Bonsai for drafts, edits and search.
2. **Replace concrete few-shot values** with placeholders or more varied examples, then re-benchmark, to stop `tomorrow 4 pm` leakage. Accept only if no previously passing case regresses.
3. **Ask for clarification explicitly**: the 2B model never emits `clarification`. Consider code-side rules (e.g. pronoun-only object "it/that/them" with no `TaskContext` → clarify) instead of relying on the model.
4. Re-run with 4B once downloaded; same fixtures, same harness.
5. Keep LM Studio's model loaded without TTL for demos, or send a warm-up request at session start (cold ≈ 5 s).
