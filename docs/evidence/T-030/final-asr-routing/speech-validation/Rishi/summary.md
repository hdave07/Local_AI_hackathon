# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:38:09Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 27/30 (90%) | 3 (2) | 0 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **3/45**. Clarification on cases where it is acceptable: 12/15 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/45 (11%), fast_path 29/45 (64%), guarded 8/45 (18%), model 3/45 (7%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 11 model calls): parseable JSON object 11/11 (100%), exact schema fields 11/11 (100%), passed strict validator 5/11 (45%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 485.0 ms, max 1765.7 ms (n=45). `clarify` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 423.0 ms. `model` p50 489.7 ms. Model call p50 458 ms, p95 1152 ms (n=11). Warm-up request: 473 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A11 | Email Sera | 1 | **unsafe** | fast_path | task create_draft(content=; recipient=Sera) |
| I18 | Change 3 to 330 | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |
| I20 | Reply to Serah that I can meet tomorrow. | 1 | **unsafe** | fast_path | task create_draft(content=I can meet tomorrow; recipient=Serah) |
| I23 | Reply to Sera, thanks, see you at 4. | 1 | **unsafe** | fast_path | task create_draft(content=thanks, see you at 4; recipient=Sera) |

## heldout-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 26/31 (84%) | 4 (2) | 1 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 4/5 (80%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 10/46 (22%), fast_path 26/46 (57%), guarded 5/46 (11%), model 5/46 (11%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 10 model calls): parseable JSON object 10/10 (100%), exact schema fields 10/10 (100%), passed strict validator 6/10 (60%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 582.3 ms, max 2140.1 ms (n=46). `clarify` p50 0.2 ms. `fast_path` p50 0.2 ms. `guarded` p50 550.7 ms. `model` p50 420.1 ms. Model call p50 475 ms, p95 1491 ms (n=10). Warm-up request: 473 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA02 | Make it dolome | 1 | wrong | model | unsupported none |
| HI02 | Go to calendar me. | 1 | wrong | guarded | clarification none “Which day or time should I check?” |
| HI05 | Open signer | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "signer") |
| HI17 | Type C you soon. | 1 | **unsafe** | fast_path | edit insert_text(text=C you soon) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI27 | Search mail for flowered confirmation. | 1 | **unsafe** | fast_path | direct read_message(query=flowered confirmation) |

## context-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 17/18 (94%) | 0 (0) | 1 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 5/5 (100%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 4/18 (22%), context 9/18 (50%), fast_path 3/18 (17%), model 2/18 (11%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 2 model calls): parseable JSON object 2/2 (100%), exact schema fields 2/2 (100%), passed strict validator 1/2 (50%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 458.2 ms, max 488.9 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `model` p50 470.8 ms. Model call p50 471 ms, p95 487 ms (n=2). Warm-up request: 473 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C02 | Switch to net. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "net") |

