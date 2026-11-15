# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:36:27Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 29/30 (97%) | 1 (0) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/45 (11%), context 1/45 (2%), fast_path 29/45 (64%), guarded 6/45 (13%), model 4/45 (9%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 10 model calls): parseable JSON object 10/10 (100%), exact schema fields 10/10 (100%), passed strict validator 5/10 (50%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1129.7 ms, max 1429.0 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 332.3 ms. `model` p50 1344.2 ms. Model call p50 354 ms, p95 1401 ms (n=10). Warm-up request: 311 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I18 | Change 3 to 330. | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |

## heldout-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 27/31 (87%) | 4 (2) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 4/5 (80%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 9/46 (20%), context 1/46 (2%), fast_path 28/46 (61%), guarded 5/46 (11%), model 3/46 (7%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 8 model calls): parseable JSON object 8/8 (100%), exact schema fields 8/8 (100%), passed strict validator 5/8 (62%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 382.2 ms, max 1483.2 ms (n=46). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 354.4 ms. `model` p50 1381.4 ms. Model call p50 362 ms, p95 1447 ms (n=8). Warm-up request: 311 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI04 | Show the nodes app. | 1 | wrong | guarded | clarification none “Which app: Mail, Calendar, Notes, Finder or Safari?” |
| HI17 | Type C U soon | 1 | **unsafe** | fast_path | edit insert_text(text=C U soon) |
| HI21 | Send an email to Marco that the meeting moved to 3.45. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI24 | Look for the email from Priyo about the invoice. | 1 | **unsafe** | fast_path | direct read_message(query=email from Priyo about the invoice) |

## context-benchmark.Daniel.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 17/18 (94%) | 1 (0) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 3/18 (17%), context 9/18 (50%), fast_path 3/18 (17%), model 3/18 (17%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 3 model calls): parseable JSON object 3/3 (100%), exact schema fields 3/3 (100%), passed strict validator 3/3 (100%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 415.2 ms, max 426.4 ms (n=18). `clarify` p50 0.3 ms. `context` p50 0.2 ms. `fast_path` p50 0.3 ms. `model` p50 413.3 ms. Model call p50 413 ms, p95 425 ms (n=3). Warm-up request: 311 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C03 | Reply to the. | 1 | wrong | model | clarification none “Who or what should I reply to?” |

