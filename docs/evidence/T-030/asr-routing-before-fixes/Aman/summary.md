# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-14T22:53:03Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Aman.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 27/30 (90%) | 1 (1) | 2 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 0 (0) | 1 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **1/45**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 0.

Routes: clarify 5/45 (11%), context 1/45 (2%), fast_path 28/45 (62%), guarded 5/45 (11%), model 6/45 (13%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 11 model calls): parseable JSON object 11/11 (100%), exact schema fields 11/11 (100%), passed strict validator 4/11 (36%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 405.2 ms, max 1333.5 ms (n=45). `clarify` p50 0.0 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 319.5 ms. `model` p50 345.4 ms. Model call p50 330 ms, p95 1318 ms (n=11). Warm-up request: 315 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A15 | Move mayor. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "mayor") |
| I01 | Open knots. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "knots") |
| I02 | Open mayor. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "mayor") |
| I18 | Change 3 2 3 30 | 1 | **unsafe** | model | edit replace_text(new=2 30; old=3) |

## heldout-benchmark.Aman.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 23/31 (74%) | 8 (4) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **4/46**. Clarification on cases where it is acceptable: 12/15 (80%). Clarification where a definite answer was expected (over-asking): 4.

Routes: clarify 8/46 (17%), context 1/46 (2%), fast_path 24/46 (52%), guarded 4/46 (9%), model 9/46 (20%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 13 model calls): parseable JSON object 13/13 (100%), exact schema fields 13/13 (100%), passed strict validator 10/13 (77%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 1286.0 ms, max 1304.6 ms (n=46). `clarify` p50 0.2 ms. `context` p50 0.2 ms. `fast_path` p50 0.2 ms. `guarded` p50 343.3 ms. `model` p50 1281.1 ms. Model call p50 367 ms, p95 1298 ms (n=13). Warm-up request: 315 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HI01 | Pier Chloe's thermal piece ahising pashimi of Riki Randinabian Leone of the Lee | 1 | wrong | model | clarification none “Which app should I open?” |
| HI04 | Sure the north app. | 1 | wrong | model | clarification none “Which app should I open?” |
| HI16 | Put the cussar in the subject field. | 1 | **unsafe** | model | direct read_message(query=cussar) |
| HI17 | Tight see you soon | 1 | wrong | model | clarification none “Which app should I open?” |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | fast_path | edit replace_text(new=2.30 p.m; old=2 p.m.) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | fast_path | task create_draft(content=the meeting moved to 345; recipient=Marco) |
| HI23 | Tell ye I'll be ten minutes late. | 1 | **unsafe** | fast_path | task create_draft(content=I'll be ten minutes late; recipient=ye) |
| HI31 | Review might apply. | 1 | wrong | model | clarification none “Which app should I review?” |

## context-benchmark.Aman.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 13/18 (72%) | 4 (0) | 1 | 0 |
| tag `negative` | 6/7 (86%) | 0 (0) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 5/5 (100%). Clarification where a definite answer was expected (over-asking): 4.

Routes: clarify 4/18 (22%), context 7/18 (39%), fast_path 1/18 (6%), guarded 1/18 (6%), model 5/18 (28%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 6 model calls): parseable JSON object 6/6 (100%), exact schema fields 6/6 (100%), passed strict validator 5/6 (83%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 1305.3 ms, max 1340.6 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 1340.6 ms. `model` p50 341.2 ms. Model call p50 801 ms, p95 1330 ms (n=6). Warm-up request: 315 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | But peace don't do. | 1 | wrong | model | clarification none “Which app should I use for peace?” |
| C02 | Switched it. | 1 | wrong | model | clarification none “Which app should I switch to?” |
| C11 | Sen | 1 | wrong | model | clarification none “Who are you speaking to?” |
| C13 | Chance that to 4 p.m. | 1 | wrong | guarded | clarification none “Do you want to check your calendar?” |
| C14 | Open mirror. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "mirror") |

