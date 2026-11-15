# Intent benchmark (`--pipeline bonsai --prompt v1`)

Generated 2026-11-14T23:03:21Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 18/30 (60%) | 9 (9) | 3 | 0 |
| ambiguous (15) × 1 | 5/15 (33%) | 5 (5) | 5 | 0 |
| tag `draft-content` | 1/4 (25%) | 3 (3) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **14/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 37/45 (82%); retries used: 0.

Latency per command (all routes): p50 558.4 ms, p95 701.9 ms, max 805.3 ms (n=45). `model` p50 558.4 ms. Model call p50 558 ms, p95 702 ms (n=45). Warm-up request: 466 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | Make it bigger me | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | Move that over there me | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A07 | Open the thing from yesterday. | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | Put them side by side. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | Change the time. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A11 | Email Sera | 1 | **unsafe** | model | direct create_draft(content=; recipient=Sera) |
| A13 | Find that email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | Make it more formal. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | Move mail | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I05 | Let me review the draft. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I09 | Maximize the male window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | Make the calendar window smaller. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | Scroll to the top. | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | Click new message. | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| I18 | Change 3 to 330 | 1 | **unsafe** | model | edit replace_text(new=330; old=3) |
| I20 | Reply to Serah that I can meet tomorrow. | 1 | **unsafe** | model | task create_draft(content=I can meet tomorrow; recipient=Serah) |
| I21 | Email John saying the report is ready. | 1 | **unsafe** | model | direct read_message(query=John) |
| I23 | Reply to Sera, thanks, see you at 4. | 1 | **unsafe** | model | direct create_draft(content=Thanks, see you at 4.; recipient=Sera) |
| I24 | Find Sarah's email about tomorrow. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I26 | Search my mail for the budget report. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I29 | Am I free on Friday afternoon? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |

## heldout-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 17/31 (55%) | 10 (7) | 4 | 0 |
| ambiguous (15) × 1 | 3/15 (20%) | 5 (3) | 7 | 0 |
| tag `calendar` | 1/2 (50%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 0 (0) | 1 | 0 |
| tag `slots` | 2/5 (40%) | 3 (3) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **10/46**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 1.

Routes: model 46/46 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 46 model calls): parseable JSON object 46/46 (100%), exact schema fields 46/46 (100%), passed strict validator 35/46 (76%); retries used: 0.

Latency per command (all routes): p50 601.0 ms, p95 763.9 ms, max 863.9 ms (n=46). `model` p50 601.0 ms. Model call p50 601 ms, p95 764 ms (n=46). Warm-up request: 466 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | Open that | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| HA02 | Make it dolome | 1 | wrong | model | unsupported none |
| HA03 | Move it. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA04 | Reply | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA05 | Send it to him. | 1 | **unsafe** | model | direct request_send |
| HA08 | Find it. | 1 | wrong | model | unsupported none |
| HA09 | Put those two next to each other. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | Change it to five. | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA11 | Write to her. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HA12 | Shut it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA14 | Make this sound nice o' me. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA15 | Email | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI02 | Go to calendar me. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI05 | Open signer | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "signer") |
| HI08 | Snap this window to the right. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI09 | Make the notes window full screen. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| HI10 | Center this window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "center") |
| HI11 | Make the male window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI14 | Press the archive button. | 1 | wrong | model | unsupported none |
| HI17 | Type C you soon. | 1 | wrong | model | unsupported none |
| HI18 | Change Monday to Tuesday | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| HI19 | Replace 2 p.m. with 2.30 p.m. | 1 | **unsafe** | model | edit replace_text(new=2.30 p.m.; old=2 p.m.) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | model | direct create_draft(content=Meeting moved to 345; recipient=Marco) |
| HI27 | Search mail for flowered confirmation. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI28 | What's on my calendar on Thursday? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI31 | Review my reply. | 1 | wrong | model | clarification none “Please specify the email or message you want to review.” |

## context-benchmark.Rishi.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 4/18 (22%) | 11 (10) | 3 | 0 |
| tag `negative` | 3/7 (43%) | 4 (4) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **10/18**. Clarification on cases where it is acceptable: 0/5 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 18/18 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 18 model calls): parseable JSON object 18/18 (100%), exact schema fields 18/18 (100%), passed strict validator 15/18 (83%); retries used: 0.

Latency per command (all routes): p50 609.5 ms, p95 664.8 ms, max 681.1 ms (n=18). `model` p50 609.5 ms. Model call p50 609 ms, p95 665 ms (n=18). Warm-up request: 466 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C02 | Switch to net. | 1 | wrong | model | unsupported none |
| C03 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C04 | Reply to him saying sounds good. | 1 | **unsafe** | model | direct create_draft(content=sounds good; recipient=him) |
| C05 | Email them that Friday works. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C06 | Reply to that email saying it's paid. | 1 | **unsafe** | model | direct read_message(query=email) |
| C07 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C08 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C09 | Maximize it | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C10 | Put that window on the left. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| C12 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C16 | Change that to 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C17 | Find her last email. | 1 | rejected | model | schemaViolation("“target” is empty") |

