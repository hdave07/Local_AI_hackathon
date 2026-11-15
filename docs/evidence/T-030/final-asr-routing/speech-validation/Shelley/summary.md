# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:39:25Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 24/30 (80%) | 6 (2) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (1) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/45**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 4.

Routes: clarify 4/45 (9%), context 1/45 (2%), fast_path 26/45 (58%), guarded 9/45 (20%), model 5/45 (11%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 14 model calls): parseable JSON object 14/14 (100%), exact schema fields 14/14 (100%), passed strict validator 8/14 (57%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1695.5 ms, max 2354.0 ms (n=45). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 443.4 ms. `model` p50 1704.4 ms. Model call p50 447 ms, p95 1964 ms (n=14). Warm-up request: 325 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I05 | Let me review the dress. | 1 | wrong | model | clarification none “Which app should I open to review the dress?” |
| I10 | Make this window a little whiter. | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| I18 | Change three to three thirty | 1 | **unsafe** | fast_path | edit replace_text(new=three thirty; old=three) |
| I22 | Write the Alex and ask if Friday works. | 1 | wrong | model | clarification none “Who is Alex and what should be asked?” |
| I23 | Reply to Sarah. Thanks, see what for. | 1 | **unsafe** | fast_path | task create_draft(content=Thanks, see what for; recipient=Sarah) |
| I24 | Fine Sarah's email about tomorrow. | 1 | wrong | guarded | clarification none “Do you want to find an email?” |

## heldout-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 25/31 (81%) | 5 (2) | 1 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 0 (0) | 1 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 1/4 (25%) | 3 (2) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (1) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 7/46 (15%), fast_path 27/46 (59%), guarded 6/46 (13%), model 6/46 (13%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 12 model calls): parseable JSON object 12/12 (100%), exact schema fields 12/12 (100%), passed strict validator 6/12 (50%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 546.9 ms, max 1870.9 ms (n=46). `clarify` p50 0.2 ms. `fast_path` p50 0.2 ms. `guarded` p50 465.1 ms. `model` p50 478.4 ms. Model call p50 465 ms, p95 1831 ms (n=12). Warm-up request: 325 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | Open lats | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "lats") |
| HI08 | Snapless window to the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "window, right") |
| HI10 | Send her this window. | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| HI12 | Scroll up a bitch. | 1 | wrong | model | unsupported none |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI22 | Write an email to Donna asking whether the twelfth still works. | 1 | **unsafe** | fast_path | task create_draft(content=asking whether the twelfth still works; recipient=Donna) |
| HI23 | Tell E, I'll be ten minutes late. | 1 | **unsafe** | fast_path | task create_draft(content=I'll be ten minutes late; recipient=E) |

## context-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 16/18 (89%) | 2 (1) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 4/18 (22%), context 8/18 (44%), fast_path 3/18 (17%), guarded 2/18 (11%), model 1/18 (6%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 3 model calls): parseable JSON object 3/3 (100%), exact schema fields 3/3 (100%), passed strict validator 3/3 (100%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1907.6 ms, max 2275.2 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.4 ms. `guarded` p50 1181.0 ms. `model` p50 2275.2 ms. Model call p50 1843 ms, p95 2232 ms (n=3). Warm-up request: 325 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C06 | Road Reply to that email saying it's paid. | 1 | **unsafe** | model | direct create_draft(content=Reply to that email saying it's paid; recipient=road) |
| C13 | Chainsla at the 4 p.m. | 1 | wrong | guarded | clarification none “Do you want to find an email?” |

