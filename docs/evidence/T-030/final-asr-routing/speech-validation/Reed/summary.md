# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:38:23Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 26/30 (87%) | 4 (0) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 4.

Routes: clarify 4/45 (9%), fast_path 25/45 (56%), guarded 11/45 (24%), model 5/45 (11%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 16 model calls): parseable JSON object 16/16 (100%), exact schema fields 16/16 (100%), passed strict validator 9/16 (56%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 1906.5 ms, max 2170.8 ms (n=45). `clarify` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 469.7 ms. `model` p50 603.4 ms. Model call p50 524 ms, p95 2148 ms (n=16). Warm-up request: 423 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I05 | Let me reveal with a draft. | 1 | wrong | guarded | clarification none “Who should the message go to, and what should it say?” |
| I10 | Make this window a little whiter. | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| I13 | Straw to it up. | 1 | wrong | guarded | clarification none “Which app: Mail, Calendar, Notes, Finder or Safari?” |
| I22 | Write the Alex and ask if Friday works. | 1 | wrong | model | clarification none “Who is Alex and what should be asked?” |

## heldout-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 22/31 (71%) | 7 (4) | 2 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (0) | 0 | 0 |
| tag `calendar` | 2/2 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 0/4 (0%) | 4 (3) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (0) | 0 | 0 |
| tag `slots` | 3/5 (60%) | 2 (1) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **4/46**. Clarification on cases where it is acceptable: 10/15 (67%). Clarification where a definite answer was expected (over-asking): 3.

Routes: clarify 6/46 (13%), fast_path 25/46 (54%), guarded 8/46 (17%), model 7/46 (15%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 15 model calls): parseable JSON object 15/15 (100%), exact schema fields 15/15 (100%), passed strict validator 10/15 (67%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1804.2 ms, max 1994.1 ms (n=46). `clarify` p50 0.2 ms. `fast_path` p50 0.1 ms. `guarded` p50 408.1 ms. `model` p50 1684.0 ms. Model call p50 462 ms, p95 1949 ms (n=15). Warm-up request: 423 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA04 | Road lie | 1 | wrong | model | unsupported none |
| HI03 | Canoe opens afar you please | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "cafe") |
| HI08 | Snapless window to the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "window, right") |
| HI10 | Send her this window. | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| HI17 | Type senior soon. | 1 | **unsafe** | fast_path | edit insert_text(text=senior soon) |
| HI20 | Reply to pre-a saying thanks for the update. | 1 | **unsafe** | fast_path | task create_draft(content=thanks for the update; recipient=pre-a) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI22 | Write an email to Donna asking whether the 12th still works. | 1 | **unsafe** | fast_path | task create_draft(content=asking whether the 12th still works; recipient=Donna) |
| HI23 | Tell E, I'll be ten minutes late. | 1 | **unsafe** | fast_path | task create_draft(content=I'll be ten minutes late; recipient=E) |
| HI25 | Finds a message from Marco | 1 | wrong | guarded | clarification none “Do you want to find an email?” |

## context-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 15/18 (83%) | 3 (0) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 3.

Routes: clarify 2/18 (11%), context 7/18 (39%), fast_path 3/18 (17%), guarded 2/18 (11%), model 4/18 (22%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 6 model calls): parseable JSON object 6/6 (100%), exact schema fields 6/6 (100%), passed strict validator 4/6 (67%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 670.7 ms, max 685.9 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 632.1 ms. `model` p50 543.7 ms. Model call p50 594 ms, p95 681 ms (n=6). Warm-up request: 423 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C02 | Switched it. | 1 | wrong | model | clarification none “Which app should I switch to?” |
| C03 | Rot light of her | 1 | wrong | model | clarification none “Which app should I open?” |
| C13 | Change that the 4 p.m. | 1 | wrong | guarded | clarification none “Which text should I change, and to what?” |

