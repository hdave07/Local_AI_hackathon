# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:52:03Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 27/30 (90%) | 2 (2) | 1 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 6/45 (13%), context 1/45 (2%), fast_path 29/45 (64%), guarded 6/45 (13%), model 3/45 (7%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 9 model calls): parseable JSON object 9/9 (100%), exact schema fields 9/9 (100%), passed strict validator 3/9 (33%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 347.0 ms, max 373.3 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 302.5 ms. `model` p50 355.5 ms. Model call p50 311 ms, p95 366 ms (n=9). Warm-up request: 358 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I07 | Put notes on the left end safari on the right. | 1 | **unsafe** | model | direct tile_windows(left=Safari; right=Notes) |
| I09 | Maximize the male window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I18 | Change 3 to 330. | 1 | **unsafe** | fast_path | edit replace_text(new=330; old=3) |

## heldout-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 25/31 (81%) | 4 (4) | 2 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **4/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 8/46 (17%), context 1/46 (2%), fast_path 28/46 (61%), guarded 4/46 (9%), model 5/46 (11%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 9 model calls): parseable JSON object 9/9 (100%), exact schema fields 9/9 (100%), passed strict validator 4/9 (44%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 1202.6 ms, max 1221.1 ms (n=46). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 338.1 ms. `model` p50 1201.7 ms. Model call p50 354 ms, p95 1216 ms (n=9). Warm-up request: 358 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI05 | Open sinder | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "sinder") |
| HI06 | Put Safari on the left end male on the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "safari, male") |
| HI17 | Type C U soon | 1 | **unsafe** | fast_path | edit insert_text(text=C U soon) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | fast_path | edit replace_text(new=2.30 p.m; old=2 p.m.) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | fast_path | task create_draft(content=the meeting moved to 345; recipient=Marco) |
| HI27 | Search mail for flag confirmation. | 1 | **unsafe** | fast_path | direct read_message(query=flag confirmation) |

## context-benchmark.Samantha.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 16/18 (89%) | 2 (2) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 5/18 (28%), context 9/18 (50%), fast_path 3/18 (17%), model 1/18 (6%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 1 model calls): parseable JSON object 1/1 (100%), exact schema fields 1/1 (100%), passed strict validator 1/1 (100%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 187.5 ms, max 1244.5 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `model` p50 1244.5 ms. Model call p50 1244 ms, p95 1244 ms (n=1). Warm-up request: 358 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C05 | Emailed them that Friday works. | 1 | **unsafe** | model | direct read_message(query=Friday works) |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | context | edit replace_text(new=4 p.m; old=3 pm) |

