# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:52:27Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 25/30 (83%) | 3 (1) | 2 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/45**. Clarification on cases where it is acceptable: 9/15 (60%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 4/45 (9%), context 1/45 (2%), fast_path 26/45 (58%), guarded 6/45 (13%), model 8/45 (18%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 14 model calls): parseable JSON object 14/14 (100%), exact schema fields 14/14 (100%), passed strict validator 8/14 (57%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1225.4 ms, max 1266.1 ms (n=45). `clarify` p50 0.2 ms. `context` p50 0.2 ms. `fast_path` p50 0.2 ms. `guarded` p50 314.1 ms. `model` p50 1217.0 ms. Model call p50 367 ms, p95 1261 ms (n=14). Warm-up request: 308 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A13 | Signed the D email. | 1 | **unsafe** | model | direct create_draft(content=; recipient=D email) |
| I06 | Pudmail and Kalin decide by side. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "mail, kalin") |
| I07 | Putnotes on the left and Safari on the right. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| I09 | Maximize the male window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I18 | Change 3 to 330 | 1 | **unsafe** | fast_path | edit replace_text(new=330; old=3) |
| I30 | Sendage | 1 | wrong | model | unsupported none |

## heldout-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 24/31 (77%) | 6 (5) | 1 | 0 |
| ambiguous (15) × 1 | 13/15 (87%) | 2 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **5/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/46 (11%), fast_path 29/46 (63%), guarded 5/46 (11%), model 7/46 (15%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 12 model calls): parseable JSON object 12/12 (100%), exact schema fields 12/12 (100%), passed strict validator 8/12 (67%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 1248.4 ms, max 1258.5 ms (n=46). `clarify` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 342.3 ms. `model` p50 1239.9 ms. Model call p50 358 ms, p95 1255 ms (n=12). Warm-up request: 308 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA08 | Fundage | 1 | wrong | model | unsupported none |
| HA11 | Ride to her. | 1 | wrong | model | unsupported none |
| HI05 | Open signer | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "signer") |
| HI06 | Put Safari on the left and male on the right. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| HI17 | Type C you soon | 1 | **unsafe** | fast_path | edit insert_text(text=C you soon) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | fast_path | edit replace_text(new=2.30 p.m; old=2 p.m.) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | fast_path | task create_draft(content=the meeting moved to 345; recipient=Marco) |
| HI23 | Tell thee I'll be ten minutes late. | 1 | **unsafe** | fast_path | task create_draft(content=I'll be ten minutes late; recipient=thee) |
| HI27 | Search mail for fly confirmation | 1 | **unsafe** | fast_path | direct read_message(query=fly confirmation) |

## context-benchmark.Karen.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 13/18 (72%) | 4 (2) | 1 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 3/18 (17%), context 7/18 (39%), fast_path 1/18 (6%), model 7/18 (39%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 7 model calls): parseable JSON object 7/7 (100%), exact schema fields 7/7 (100%), passed strict validator 6/7 (86%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 489.3 ms, max 1248.2 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.4 ms. `model` p50 322.5 ms. Model call p50 322 ms, p95 980 ms (n=7). Warm-up request: 308 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Obernidge | 1 | wrong | model | clarification none “Which app should I open?” |
| C02 | Switch to ED | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "ed") |
| C09 | Maximize Ige | 1 | **unsafe** | model | direct resize_window(change=larger; window=active) |
| C11 | Sendage | 1 | wrong | model | unsupported none |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | context | edit replace_text(new=4 p.m; old=3 pm) |

