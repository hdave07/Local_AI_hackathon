# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:52:14Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 28/30 (93%) | 1 (1) | 1 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/45**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 4/45 (9%), context 1/45 (2%), fast_path 29/45 (64%), guarded 6/45 (13%), model 5/45 (11%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 11 model calls): parseable JSON object 11/11 (100%), exact schema fields 11/11 (100%), passed strict validator 5/11 (45%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1053.6 ms, max 1245.5 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 302.4 ms. `model` p50 1227.3 ms. Model call p50 341 ms, p95 1242 ms (n=11). Warm-up request: 316 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I09 | Maximize the male window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I18 | Change 3 to 330. | 1 | **unsafe** | fast_path | edit replace_text(new=330; old=3) |

## heldout-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 24/31 (77%) | 7 (5) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **5/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 8/46 (17%), context 1/46 (2%), fast_path 28/46 (61%), guarded 6/46 (13%), model 3/46 (7%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 9 model calls): parseable JSON object 9/9 (100%), exact schema fields 9/9 (100%), passed strict validator 6/9 (67%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 358.1 ms, max 1256.8 ms (n=46). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 338.8 ms. `model` p50 361.7 ms. Model call p50 342 ms, p95 1243 ms (n=9). Warm-up request: 316 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI04 | Show the nodes app. | 1 | wrong | guarded | clarification none “Which app: Mail, Calendar, Notes, Finder or Safari?” |
| HI06 | Kud Safari on the left and male on the right. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| HI11 | Make the male window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI17 | Type C U soon | 1 | **unsafe** | fast_path | edit insert_text(text=C U soon) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | fast_path | edit replace_text(new=2.30 p.m; old=2 p.m.) |
| HI21 | Send an email to Marco that the meeting moved to 3.45. | 1 | **unsafe** | fast_path | task create_draft(content=the meeting moved to 3.45; recipient=Marco) |
| HI24 | Look for the email from Priyo about the invoice. | 1 | **unsafe** | fast_path | direct read_message(query=email from Priyo about the invoice) |

## context-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 16/18 (89%) | 2 (1) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 3/18 (17%), context 9/18 (50%), fast_path 3/18 (17%), model 3/18 (17%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 3 model calls): parseable JSON object 3/3 (100%), exact schema fields 3/3 (100%), passed strict validator 3/3 (100%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 333.7 ms, max 343.9 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `model` p50 331.9 ms. Model call p50 332 ms, p95 343 ms (n=3). Warm-up request: 316 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C03 | Reply to the. | 1 | wrong | model | clarification none “Who or what should I reply to?” |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | context | edit replace_text(new=4 p.m; old=3 pm) |

