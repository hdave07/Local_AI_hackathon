# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:41:38Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 3 | 90/90 (100%) | 0 (0) | 0 | 0 |
| ambiguous (15) × 3 | 45/45 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 12/12 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/135**. Clarification on cases where it is acceptable: 30/45 (67%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 18/135 (13%), context 3/135 (2%), fast_path 93/135 (69%), guarded 18/135 (13%), model 3/135 (2%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 21 model calls): parseable JSON object 21/21 (100%), exact schema fields 21/21 (100%), passed strict validator 6/21 (29%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 321.6 ms, max 349.0 ms (n=135). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 311.5 ms. `model` p50 334.5 ms. Model call p50 316 ms, p95 340 ms (n=21). Warm-up request: 310 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

## heldout-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 3 | 93/93 (100%) | 0 (0) | 0 | 0 |
| ambiguous (15) × 3 | 45/45 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 6/6 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 15/15 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/138**. Clarification on cases where it is acceptable: 33/45 (73%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 27/138 (20%), context 3/138 (2%), fast_path 93/138 (67%), guarded 12/138 (9%), model 3/138 (2%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 15 model calls): parseable JSON object 15/15 (100%), exact schema fields 15/15 (100%), passed strict validator 6/15 (40%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 312.8 ms, max 361.3 ms (n=138). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 326.5 ms. `model` p50 299.1 ms. Model call p50 312 ms, p95 350 ms (n=15). Warm-up request: 310 ms.

## context-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 3 | 54/54 (100%) | 0 (0) | 0 | 0 |
| tag `negative` | 21/21 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/54**. Clarification on cases where it is acceptable: 12/15 (80%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 15/54 (28%), context 30/54 (56%), fast_path 9/54 (17%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

Latency per command (all routes): p50 0.1 ms, p95 0.1 ms, max 0.1 ms (n=54). `clarify` p50 0.0 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. Warm-up request: 310 ms.

