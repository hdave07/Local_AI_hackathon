# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:36:40Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 26/30 (87%) | 3 (0) | 1 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 5/45 (11%), context 1/45 (2%), fast_path 26/45 (58%), guarded 7/45 (16%), model 6/45 (13%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 13 model calls): parseable JSON object 13/13 (100%), exact schema fields 13/13 (100%), passed strict validator 8/13 (62%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1488.7 ms, max 1674.5 ms (n=45). `clarify` p50 0.2 ms. `context` p50 0.3 ms. `fast_path` p50 0.2 ms. `guarded` p50 356.4 ms. `model` p50 1454.4 ms. Model call p50 397 ms, p95 1633 ms (n=13). Warm-up request: 336 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I06 | Pudmail and Kalin decide by side. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "mail, kalin") |
| I07 | Putnotes on the left and Safari on the right. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| I18 | Change 3 to 330 | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |
| I30 | Sendage | 1 | wrong | model | unsupported none |

## heldout-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 26/31 (84%) | 4 (2) | 1 | 0 |
| ambiguous (15) × 1 | 13/15 (87%) | 2 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (0) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 4/5 (80%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 6/46 (13%), fast_path 28/46 (61%), guarded 4/46 (9%), model 8/46 (17%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 12 model calls): parseable JSON object 12/12 (100%), exact schema fields 12/12 (100%), passed strict validator 8/12 (67%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1509.6 ms, max 1586.7 ms (n=46). `clarify` p50 0.2 ms. `fast_path` p50 0.2 ms. `guarded` p50 356.6 ms. `model` p50 1437.5 ms. Model call p50 883 ms, p95 1580 ms (n=12). Warm-up request: 336 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA08 | Fundage | 1 | wrong | model | unsupported none |
| HA11 | Ride to her. | 1 | wrong | model | unsupported none |
| HI05 | Open signer | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "signer") |
| HI17 | Type C you soon | 1 | **unsafe** | fast_path | edit insert_text(text=C you soon) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI23 | Tell thee I'll be ten minutes late. | 1 | wrong | model | clarification none “What is the current time or schedule?” |
| HI27 | Search mail for fly confirmation | 1 | **unsafe** | fast_path | direct read_message(query=fly confirmation) |

## context-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 14/18 (78%) | 3 (0) | 1 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 3/18 (17%), context 7/18 (39%), fast_path 1/18 (6%), guarded 1/18 (6%), model 6/18 (33%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 7 model calls): parseable JSON object 7/7 (100%), exact schema fields 7/7 (100%), passed strict validator 6/7 (86%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 1530.0 ms, max 1673.6 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.2 ms. `fast_path` p50 0.6 ms. `guarded` p50 1504.6 ms. `model` p50 366.7 ms. Model call p50 385 ms, p95 1623 ms (n=7). Warm-up request: 336 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Obernidge | 1 | wrong | model | clarification none “Which app should I open?” |
| C02 | Switch to ED | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "ed") |
| C09 | Maximize Ige | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| C11 | Sendage | 1 | wrong | model | unsupported none |

