# Intent benchmark (`--pipeline bonsai --prompt v1`)

Generated 2026-11-14T23:06:43Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 18/30 (60%) | 8 (8) | 4 | 0 |
| ambiguous (15) × 1 | 4/15 (27%) | 4 (4) | 7 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **12/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 34/45 (76%); retries used: 0.

Latency per command (all routes): p50 599.8 ms, p95 669.0 ms, max 692.2 ms (n=45). `model` p50 599.8 ms. Model call p50 600 ms, p95 669 ms (n=45). Warm-up request: 540 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | Make it bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | Move lad over there. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A05 | Believe that. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A07 | Open the thing from yesterday. | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | Put them side by side. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | Change the time | 1 | rejected | model | schemaViolation("“target” is empty") |
| A12 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A13 | Finds that email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | Make it more formal. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | Move mail | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I05 | Let me review the dress. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| I09 | Maximize the male window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I10 | Make this window a little whiter. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I11 | Make the calendar window smaller. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | Scroll to the top. | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | Click new message. | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| I16 | Focus the searched field. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I21 | Email John saying the report is ready. | 1 | **unsafe** | model | direct read_message(query=John) |
| I23 | Reply to Sarah. Thanks, see what for. | 1 | **unsafe** | model | direct create_draft(content=Thanks, see what for.; recipient=sarah) |
| I24 | Fine Sarah's email about tomorrow. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I26 | Search my mail for the budget report. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I29 | Am I free on Friday afternoons? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |

## heldout-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 16/31 (52%) | 10 (7) | 5 | 0 |
| ambiguous (15) × 1 | 5/15 (33%) | 3 (2) | 7 | 0 |
| tag `calendar` | 1/2 (50%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 1/4 (25%) | 2 (2) | 1 | 0 |
| tag `email-search` | 3/4 (75%) | 0 (0) | 1 | 0 |
| tag `slots` | 1/5 (20%) | 4 (4) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **9/46**. Clarification on cases where it is acceptable: 1/15 (7%). Clarification where a definite answer was expected (over-asking): 1.

Routes: model 46/46 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 46 model calls): parseable JSON object 46/46 (100%), exact schema fields 46/46 (100%), passed strict validator 34/46 (74%); retries used: 0.

Latency per command (all routes): p50 607.1 ms, p95 785.4 ms, max 890.4 ms (n=46). `model` p50 607.1 ms. Model call p50 607 ms, p95 785 ms (n=46). Warm-up request: 540 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | Open lats | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "lats") |
| HA03 | Move it. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA04 | Reply | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA05 | Send the to them. | 1 | **unsafe** | model | direct request_send |
| HA08 | Find it. | 1 | wrong | model | unsupported none |
| HA09 | Point Put those two next to each other. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | Change it to 5. | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA12 | Shut it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA14 | Make this sound nicer. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA15 | Email | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI02 | Go to calendar | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI08 | Snapless window to the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "window") |
| HI09 | Make the notes window full screen. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| HI10 | Send her this window. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "active") |
| HI11 | Make the male window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI12 | Scroll up a bitch. | 1 | wrong | model | unsupported none |
| HI14 | Press the archive button. | 1 | wrong | model | unsupported none |
| HI18 | Change Monday to Tuesday | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| HI19 | Replace 2 p.m. with 2.30 PM | 1 | **unsafe** | model | edit replace_text(new=2.30 PM; old=2) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | model | direct create_draft(content=Meeting moved to 345; recipient=Marco) |
| HI22 | Write an email to Donna asking whether the twelfth still works. | 1 | **unsafe** | model | direct create_draft(content=Is the twelfth still working?; recipient=Donna) |
| HI23 | Tell E, I'll be ten minutes late. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HI27 | Search mail for flight confirmation. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI28 | What's on my calendar on Thursday? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI31 | Review my reply. | 1 | wrong | model | clarification none “Please specify the email or message you want to review.” |

## context-benchmark.Shelley (English (US)).p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 3/18 (17%) | 12 (12) | 3 | 0 |
| tag `negative` | 2/7 (29%) | 4 (4) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **12/18**. Clarification on cases where it is acceptable: 0/5 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 18/18 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 18 model calls): parseable JSON object 18/18 (100%), exact schema fields 18/18 (100%), passed strict validator 15/18 (83%); retries used: 0.

Latency per command (all routes): p50 598.3 ms, p95 639.5 ms, max 654.4 ms (n=18). `model` p50 598.3 ms. Model call p50 598 ms, p95 640 ms (n=18). Warm-up request: 540 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C02 | Switch to it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C03 | Reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C04 | Reply to them say he sounds good. | 1 | **unsafe** | model | direct create_draft(content=He sounds good; recipient=them) |
| C05 | Email them at Friday works. | 1 | **unsafe** | model | direct create_draft(content=Friday works; recipient=sarah) |
| C06 | Road Reply to that email saying it's paid. | 1 | **unsafe** | model | direct read_message(query=email) |
| C07 | Reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C08 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C09 | Maximize it. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C10 | Put that window on the left. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| C12 | Reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C13 | Chainsla at the 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C16 | Chainsla at the 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C17 | Find her last email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C18 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |

