# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:36:08Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 29/30 (97%) | 1 (0) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 7/45 (16%), context 1/45 (2%), fast_path 30/45 (67%), guarded 6/45 (13%), model 1/45 (2%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 7 model calls): parseable JSON object 7/7 (100%), exact schema fields 7/7 (100%), passed strict validator 2/7 (29%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 1451.3 ms, max 1484.2 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 1415.0 ms. `model` p50 1484.2 ms. Model call p50 1433 ms, p95 1483 ms (n=7). Warm-up request: 550 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I18 | Change 3 to 330. | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |

## heldout-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 27/31 (87%) | 3 (2) | 1 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 4/5 (80%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 9/46 (20%), context 1/46 (2%), fast_path 28/46 (61%), guarded 4/46 (9%), model 4/46 (9%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 8 model calls): parseable JSON object 8/8 (100%), exact schema fields 8/8 (100%), passed strict validator 4/8 (50%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1337.6 ms, max 1418.9 ms (n=46). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 361.2 ms. `model` p50 1370.5 ms. Model call p50 839 ms, p95 1411 ms (n=8). Warm-up request: 550 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI05 | Open sinder | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "sinder") |
| HI17 | Type C U soon | 1 | **unsafe** | fast_path | edit insert_text(text=C U soon) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI27 | Search mail for flag confirmation. | 1 | **unsafe** | fast_path | direct read_message(query=flag confirmation) |

## context-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 17/18 (94%) | 1 (0) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/18 (28%), context 9/18 (50%), fast_path 3/18 (17%), guarded 1/18 (6%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 1 model calls): parseable JSON object 1/1 (100%), exact schema fields 1/1 (100%), passed strict validator 1/1 (100%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 201.5 ms, max 1341.6 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 1341.6 ms. Model call p50 1341 ms, p95 1341 ms (n=1). Warm-up request: 550 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C05 | Emailed them that Friday works. | 1 | wrong | guarded | clarification none “Do you want to find an email?” |

