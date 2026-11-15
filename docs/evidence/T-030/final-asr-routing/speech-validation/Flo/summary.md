# Intent benchmark (`--pipeline router --prompt v2`)

Generated 2026-11-15T00:38:57Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Flo (English (UK)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 26/30 (87%) | 4 (0) | 0 | 0 |
| ambiguous (15) × 1 | 15/15 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 4/4 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/45**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 4.

Routes: clarify 5/45 (11%), context 1/45 (2%), fast_path 27/45 (60%), guarded 9/45 (20%), model 3/45 (7%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 12 model calls): parseable JSON object 12/12 (100%), exact schema fields 12/12 (100%), passed strict validator 8/12 (67%); retries used: 0.

Latency per command (all routes): p50 0.3 ms, p95 1600.9 ms, max 2155.0 ms (n=45). `clarify` p50 0.2 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 510.4 ms. `model` p50 2140.0 ms. Model call p50 525 ms, p95 2146 ms (n=12). Warm-up request: 489 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| I03 | Who owns calendar? | 1 | wrong | model | clarification none “Who owns the calendar?” |
| I06 | Put male and camonda side by side. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| I18 | Change 3 to 330. | 1 | wrong | clarify | clarification none “Did you mean 3:30? Say yes, or no to keep it as heard.” |
| I24 | Fine Sarah's email about tomorrow. | 1 | wrong | guarded | clarification none “Do you want to find an email?” |

## heldout-benchmark.Flo (English (UK)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 21/31 (68%) | 9 (4) | 1 | 0 |
| ambiguous (15) × 1 | 14/15 (93%) | 1 (0) | 0 | 0 |
| tag `calendar` | 1/2 (50%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 0/4 (0%) | 4 (2) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `slots` | 2/5 (40%) | 3 (2) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **4/46**. Clarification on cases where it is acceptable: 11/15 (73%). Clarification where a definite answer was expected (over-asking): 5.

Routes: clarify 7/46 (15%), fast_path 24/46 (52%), guarded 8/46 (17%), model 7/46 (15%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 15 model calls): parseable JSON object 15/15 (100%), exact schema fields 15/15 (100%), passed strict validator 9/15 (60%); retries used: 0.

Latency per command (all routes): p50 0.2 ms, p95 1805.4 ms, max 2056.9 ms (n=46). `clarify` p50 0.2 ms. `fast_path` p50 0.1 ms. `guarded` p50 451.6 ms. `model` p50 568.9 ms. Model call p50 453 ms, p95 1944 ms (n=15). Warm-up request: 489 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA02 | Make a Torah. | 1 | wrong | model | unsupported none |
| HI09 | Make a notes window full screen. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "full screen") |
| HI11 | Make a male window bigger. | 1 | wrong | guarded | clarification none “Wider, narrower, taller, shorter, bigger or smaller?” |
| HI12 | Stroll up a bit. | 1 | wrong | guarded | clarification none “I didn't catch what to do. Could you say it another way?” |
| HI20 | Reply to previous saying thanks for the update. | 1 | **unsafe** | fast_path | task create_draft(content=thanks for the update; recipient=previous) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | wrong | clarify | clarification none “Did you mean 3:45? Say yes, or no to keep it as heard.” |
| HI22 | Write an email to Donna asking whether the twelfth still works. | 1 | **unsafe** | fast_path | task create_draft(content=asking whether the twelfth still works; recipient=Donna) |
| HI23 | Tell thee I'll be ten minutes late. | 1 | wrong | model | clarification none “What is the current time or schedule?” |
| HI24 | Look for the email from prehere about the invoice. | 1 | **unsafe** | fast_path | direct read_message(query=email from prehere about the invoice) |
| HI29 | Am I busy at ten AM to morrow? | 1 | **unsafe** | fast_path | direct query_calendar(time=at ten AM to morrow) |
| HI31 | Resume my reply. | 1 | wrong | guarded | clarification none “Which email should I look for?” |

## context-benchmark.Flo (English (UK)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 16/18 (89%) | 2 (0) | 0 | 0 |
| tag `negative` | 7/7 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **0/18**. Clarification on cases where it is acceptable: 4/5 (80%). Clarification where a definite answer was expected (over-asking): 2.

Routes: clarify 5/18 (28%), context 8/18 (44%), fast_path 3/18 (17%), guarded 2/18 (11%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 2 model calls): parseable JSON object 2/2 (100%), exact schema fields 2/2 (100%), passed strict validator 2/2 (100%); retries used: 0.

Latency per command (all routes): p50 0.1 ms, p95 1665.0 ms, max 1843.4 ms (n=18). `clarify` p50 0.1 ms. `context` p50 0.1 ms. `fast_path` p50 0.2 ms. `guarded` p50 1738.5 ms. Model call p50 1738 ms, p95 1832 ms (n=2). Warm-up request: 489 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C10 | Puts at the window on the left. | 1 | wrong | guarded | clarification none “Which two apps should go side by side?” |
| C17 | Find her lost email. | 1 | wrong | guarded | clarification none “Who do you mean?” |

