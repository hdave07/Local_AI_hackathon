# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:52:49Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 27/30 (90%) | 2 (1) | 1 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 3/45 (7%), context 1/45 (2%), fast_path 27/45 (60%), guarded 7/45 (16%), model 7/45 (16%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 14 model calls): parseable JSON object 14/14 (100%), exact schema fields 14/14 (100%), passed strict validator 7/14 (50%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1072.7 ms, max 1268.8 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 319.4 ms. `model` p50 314.7 ms. Model call p50 317 ms, p95 1264 ms (n=14). Warm-up request: 310 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I09 | Maximize the male window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I17 | Tight hello everyone. | 1 | wrong | model | clarification none “Who are you talking to?” |
| I18 | Change 3 to 330 | 1 | **unsafe** | fast_path | edit replace_text(new=330; old=3) |

## heldout-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 26/31 (84%) | 5 (4) | 0 | 0 |
| ambiguous (15) × 1 | 13/15 (87%) | 0 (0) | 2 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **4/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/46 (11%), context 1/46 (2%), fast_path 29/46 (63%), guarded 5/46 (11%), model 6/46 (13%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 11 model calls): parseable JSON object 11/11 (100%), exact schema fields 11/11 (100%), passed strict validator 6/11 (55%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 355.9 ms, max 1269.8 ms (n=46). `clarify` p50 0.2 ms. `context` p50 0.3 ms. `fast_path` p50 0.1 ms. `guarded` p50 349.0 ms. `model` p50 325.9 ms. Model call p50 327 ms, p95 814 ms (n=11). Warm-up request: 310 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA03 | Movis | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "mavis") |
| HA08 | Finders | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "finders") |
| HI06 | Put Safari on the left and male on the right. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| HI11 | Make the male window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | fast_path | edit replace_text(new=2.30 p.m; old=2 p.m.) |
| HI20 | Reply to pre-assaying thanks for the update. | 1 | **unsafe** | fast_path | task create_draft(content=thanks for the update; recipient=pre-assaying) |
| HI21 | Send an email to Marco that the meeting moved to 3.45. | 1 | **unsafe** | fast_path | task create_draft(content=the meeting moved to 3.45; recipient=Marco) |

## context-benchmark.Moira.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 14/18 (78%) | 3 (1) | 1 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 3/18 (17%), context 7/18 (39%), fast_path 2/18 (11%), model 6/18 (33%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 6 model calls): parseable JSON object 6/6 (100%), exact schema fields 6/6 (100%), passed strict validator 5/6 (83%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 341.3 ms, max 364.2 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.2 ms. `fast_path` p50 0.4 ms. `model` p50 318.5 ms. Model call p50 318 ms, p95 357 ms (n=6). Warm-up request: 310 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Openness | 1 | wrong | model | clarification none “Which app should I open?” |
| C02 | Switch to is. | 1 | wrong | model | clarification none “Which app should I switch to?” |
| C09 | Maximizes | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | context | edit replace_text(new=4 p.m; old=3 pm) |

