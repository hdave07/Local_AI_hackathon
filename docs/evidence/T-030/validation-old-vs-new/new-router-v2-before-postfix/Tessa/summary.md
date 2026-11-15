# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T23:07:51Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 25/30 (83%) | 4 (2) | 1 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **3/45**. Clarification on cases where it is acceptable: 9/15 (60%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 6/45 (13%), context 1/45 (2%), fast_path 27/45 (60%), guarded 6/45 (13%), model 5/45 (11%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 11 model calls): parseable JSON object 11/11 (100%), exact schema fields 11/11 (100%), passed strict validator 5/11 (45%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1640.1 ms, max 2276.7 ms (n=45). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 466.7 ms. `model` p50 1885.8 ms. Model call p50 501 ms, p95 2220 ms (n=11). Warm-up request: 398 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A11 | Email Sira | 1 | **unsafe** | fast_path | task create_draft(content=; recipient=Sira) |
| I13 | Scroll to the chomp | 1 | rejected | model | unsupportedTarget(action: "scroll", target: "chomp") |
| I18 | Change 3 to 330. | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |
| I19 | Replaced Us Day with Wednesday. | 1 | **unsafe** | model | edit replace_text(new=Wednesday; old=Us Day) |
| I23 | Reply to Sira, thanks, see you at 4. | 1 | **unsafe** | fast_path | task create_draft(content=thanks, see you at 4; recipient=Sira) |
| I30 | Sengat | 1 | wrong | model | clarification none “Who or what are you referring to?” |

## heldout-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 26/31 (84%) | 5 (2) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **2/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 3.

Routes: clarify 10/46 (22%), context 1/46 (2%), fast_path 26/46 (57%), guarded 5/46 (11%), model 4/46 (9%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 9 model calls): parseable JSON object 9/9 (100%), exact schema fields 9/9 (100%), passed strict validator 5/9 (56%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 1798.3 ms, max 2084.3 ms (n=46). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.1 ms. `guarded` p50 402.9 ms. `model` p50 1783.2 ms. Model call p50 473 ms, p95 1989 ms (n=9). Warm-up request: 398 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI12 | Scroll after bit. | 1 | **unsafe** | model | direct scroll(direction=down) |
| HI17 | Type C U soon. | 1 | **unsafe** | fast_path | edit insert_text(text=C U soon) |
| HI19 | Replace 2 PM with 230 PM. | 1 | wrong | clarify | clarification none “Did you mean 2:30? Say yes, or no to keep it as heard.” |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI30 | Sing the draft | 1 | wrong | guarded | clarification none “Who should the message go to, and what should it say?” |

## context-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 15/18 (83%) | 1 (0) | 2 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 1.

Routes: clarify 5/18 (28%), context 8/18 (44%), fast_path 2/18 (11%), model 3/18 (17%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 3 model calls): parseable JSON object 3/3 (100%), exact schema fields 3/3 (100%), passed strict validator 1/3 (33%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 441.7 ms, max 497.3 ms (n=18). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.3 ms. `model` p50 431.9 ms. Model call p50 432 ms, p95 491 ms (n=3). Warm-up request: 398 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C02 | Switch to nit. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "nit") |
| C10 | Put that window on the list. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "active") |
| C11 | Sengat | 1 | wrong | model | clarification none “Who or what are you referring to?” |

