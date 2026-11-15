# Intent benchmark (`--pipeline bonsai --prompt v1`)

Generated 2026-11-14T23:04:27Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 20/30 (67%) | 7 (6) | 3 | 0 |
| ambiguous (15) × 1 | 4/15 (27%) | 5 (4) | 6 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **10/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 36/45 (80%); retries used: 0.

Latency per command (all routes): p50 648.7 ms, p95 829.8 ms, max 866.4 ms (n=45). `model` p50 648.7 ms. Model call p50 649 ms, p95 830 ms (n=45). Warm-up request: 668 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | Make it better. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A03 | Move that over there. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A04 | Rot light of her | 1 | wrong | model | unsupported none |
| A07 | Open the thing from yesterday. | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | Put them side by side. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | Change the time. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A12 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A13 | Finds that email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | Make it more formal. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | Move mail | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I05 | Let me reveal with a draft. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I09 | Maximize the male window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I10 | Make this window a little whiter. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I11 | Make the calendar window smaller. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | Straw to it up. | 1 | wrong | model | unsupported none |
| I15 | Click new message. | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| I21 | Email John saying the report is ready. | 1 | **unsafe** | model | direct read_message(query=John) |
| I24 | Find Sarah's email about tomorrow. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I26 | Search my mail for the budget report. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I29 | Am I free on Friday afternoon? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |

## heldout-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 13/31 (42%) | 12 (9) | 6 | 0 |
| ambiguous (15) × 1 | 4/15 (27%) | 6 (3) | 5 | 0 |
| tag `calendar` | 1/2 (50%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 0/4 (0%) | 3 (3) | 1 | 0 |
| tag `email-search` | 2/4 (50%) | 0 (0) | 2 | 0 |
| tag `slots` | 1/5 (20%) | 4 (4) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **12/46**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 1.

Routes: model 46/46 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 46 model calls): parseable JSON object 46/46 (100%), exact schema fields 46/46 (100%), passed strict validator 35/46 (76%); retries used: 0.

Latency per command (all routes): p50 618.6 ms, p95 916.5 ms, max 1059.1 ms (n=46). `model` p50 618.6 ms. Model call p50 619 ms, p95 916 ms (n=46). Warm-up request: 668 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | Open lat | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| HA03 | Move it. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA04 | Road lie | 1 | wrong | model | unsupported none |
| HA05 | Send the term | 1 | wrong | model | unsupported none |
| HA08 | Find it. | 1 | wrong | model | unsupported none |
| HA09 | Put those two next to each other. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | Change it to 5. | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA11 | Right of her | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA12 | Shut it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA14 | Make this sound nicer. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA15 | Email | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI02 | Go to calendar | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI03 | Canoe opens afar you please | 1 | wrong | model | unsupported none |
| HI08 | Snapless window to the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "window") |
| HI09 | Make the notes window full screen. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| HI10 | Send her this window. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "active") |
| HI11 | Make the mail window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=Mail) |
| HI14 | Press the archive button. | 1 | wrong | model | unsupported none |
| HI17 | Type senior soon. | 1 | **unsafe** | model | direct insert_text(text=senior soon) |
| HI18 | Change Monday to Tuesday. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | model | edit replace_text(new=2.30 p.m.; old=2 p.m.) |
| HI20 | Reply to pre-a saying thanks for the update. | 1 | **unsafe** | model | direct create_draft(content=Thanks for the update.; recipient=pre-a) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | model | direct create_draft(content=Meeting moved to 345; recipient=Marco) |
| HI22 | Write an email to Donna asking whether the 12th still works. | 1 | **unsafe** | model | direct create_draft(content=Is the 12th still working?; recipient=Donna) |
| HI23 | Tell E, I'll be ten minutes late. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HI25 | Finds a message from Marco | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI27 | Search mail for flight confirmation. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI28 | What's on my calendar on Thursday? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI31 | Review my reply. | 1 | wrong | model | clarification none “Please specify the email or message you want to review.” |

## context-benchmark.Reed (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 3/18 (17%) | 11 (7) | 4 | 0 |
| tag `negative` | 2/7 (29%) | 4 (2) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **7/18**. Clarification on cases where it is acceptable: 0/5 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 18/18 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 18 model calls): parseable JSON object 18/18 (100%), exact schema fields 18/18 (100%), passed strict validator 14/18 (78%); retries used: 0.

Latency per command (all routes): p50 589.8 ms, p95 658.0 ms, max 658.3 ms (n=18). `model` p50 589.8 ms. Model call p50 590 ms, p95 658 ms (n=18). Warm-up request: 668 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C02 | Switched it. | 1 | wrong | model | unsupported none |
| C03 | Rot light of her | 1 | wrong | model | unsupported none |
| C04 | Reply to him saying sounds good. | 1 | **unsafe** | model | direct create_draft(content=sounds good; recipient=him) |
| C05 | Email them that Friday works. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C06 | Reply to that email saying it's paid. | 1 | **unsafe** | model | direct read_message(query=email) |
| C07 | Rot light of her | 1 | wrong | model | unsupported none |
| C08 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C09 | Maximize it. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C10 | Put that window on the left. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| C12 | Rot light of her | 1 | wrong | model | unsupported none |
| C13 | Change that the 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C16 | Change that the 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C17 | Find her last email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C18 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |

