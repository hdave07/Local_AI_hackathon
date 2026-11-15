# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:37:07Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 28/30 (93%) | 2 (0) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 4/45 (9%), context 1/45 (2%), fast_path 27/45 (60%), guarded 7/45 (16%), model 6/45 (13%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 13 model calls): parseable JSON object 13/13 (100%), exact schema fields 13/13 (100%), passed strict validator 7/13 (54%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1210.1 ms, max 1681.4 ms (n=45). `clarify` p50 0.2 ms. `context` p50 0.3 ms. `fast_path` p50 0.2 ms. `guarded` p50 395.2 ms. `model` p50 367.7 ms. Model call p50 393 ms, p95 1627 ms (n=13). Warm-up request: 386 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I17 | Tight hello everyone. | 1 | wrong | model | clarification none “Who are you talking to?” |
| I18 | Change 3 to 330 | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |

## heldout-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 29/31 (94%) | 2 (1) | 0 | 0 |
| ambiguous (15) × 1 | 13/15 (87%) | 0 (0) | 2 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (1) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 4/5 (80%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 6/46 (13%), context 1/46 (2%), fast_path 30/46 (65%), guarded 4/46 (9%), model 5/46 (11%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 9 model calls): parseable JSON object 9/9 (100%), exact schema fields 9/9 (100%), passed strict validator 4/9 (44%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 412.5 ms, max 1537.7 ms (n=46). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 408.2 ms. `model` p50 374.6 ms. Model call p50 401 ms, p95 1115 ms (n=9). Warm-up request: 386 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA03 | Movis | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "mavis") |
| HA08 | Finders | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "finders") |
| HI20 | Reply to pre-assaying thanks for the update. | 1 | **unsafe** | fast_path | task create_draft(content=thanks for the update; recipient=pre-assaying) |
| HI21 | Send an email to Marco that the meeting moved to 3.45. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |

## context-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 15/18 (83%) | 2 (0) | 1 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 3/18 (17%), context 7/18 (39%), fast_path 2/18 (11%), model 6/18 (33%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 6 model calls): parseable JSON object 6/6 (100%), exact schema fields 6/6 (100%), passed strict validator 5/6 (83%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 393.0 ms, max 430.0 ms (n=18). `clarify` p50 0.3 ms. `context` p50 0.2 ms. `fast_path` p50 0.3 ms. `model` p50 365.6 ms. Model call p50 365 ms, p95 419 ms (n=6). Warm-up request: 386 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Openness | 1 | wrong | model | clarification none “Which app should I open?” |
| C02 | Switch to is. | 1 | wrong | model | clarification none “Which app should I switch to?” |
| C09 | Maximizes | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |

