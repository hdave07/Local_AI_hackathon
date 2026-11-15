# Intent benchmark (`--pipeline bonsai --prompt v1`)

Generated 2026-11-14T23:02:13Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 17/30 (57%) | 10 (9) | 3 | 0 |
| ambiguous (15) × 1 | 4/15 (27%) | 4 (4) | 7 | 0 |
| tag `draft-content` | 2/4 (50%) | 2 (2) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **13/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 35/45 (78%); retries used: 0.

Latency per command (all routes): p50 483.8 ms, p95 1820.5 ms, max 2269.1 ms (n=45). `model` p50 483.8 ms. Model call p50 484 ms, p95 1820 ms (n=45). Warm-up request: 1476 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | Make it bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | Move that over there | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A07 | Open the thing from yesterday. | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | Put them side by side. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | Change the time. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A11 | Email Sira | 1 | rejected | model | schemaViolation("“target” is empty") |
| A12 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A13 | Find that email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | Make it more formal. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | Move mail. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I05 | Let me review the draft. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I09 | Maximize the male window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | Make the calendar window smaller. | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | Scroll to the chomp | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | Click new message. | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| I18 | Change 3 to 330. | 1 | **unsafe** | model | edit replace_text(new=330; old=3) |
| I19 | Replaced Us Day with Wednesday. | 1 | **unsafe** | model | edit replace_text(new=Wednesday; old=Us Day) |
| I21 | Email John saying the report is ready. | 1 | **unsafe** | model | direct read_message(query=John) |
| I23 | Reply to Sira, thanks, see you at 4. | 1 | **unsafe** | model | direct create_draft(content=Thanks, see you at 4.; recipient=Sira) |
| I24 | Find Sarah's email about tomorrow. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I26 | Search my mail for the budget report. | 1 | rejected | model | schemaViolation("“target” is empty") |
| I29 | Am I free on Friday afternoon? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I30 | Sengat | 1 | wrong | model | unsupported none |

## heldout-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 1 | 15/31 (48%) | 11 (9) | 5 | 0 |
| ambiguous (15) × 1 | 6/15 (40%) | 4 (3) | 5 | 0 |
| tag `calendar` | 1/2 (50%) | 1 (1) | 0 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 3/4 (75%) | 0 (0) | 1 | 0 |
| tag `slots` | 2/5 (40%) | 3 (3) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **12/46**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 1.

Routes: model 46/46 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 46 model calls): parseable JSON object 46/46 (100%), exact schema fields 46/46 (100%), passed strict validator 36/46 (78%); retries used: 0.

Latency per command (all routes): p50 552.7 ms, p95 818.6 ms, max 953.5 ms (n=46). `model` p50 552.7 ms. Model call p50 553 ms, p95 819 ms (n=46). Warm-up request: 1476 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | Open that. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| HA03 | Move it. | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA04 | Reply. | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA05 | Send it to him. | 1 | **unsafe** | model | direct request_send |
| HA08 | Find it. | 1 | wrong | model | unsupported none |
| HA09 | Put those two next to each other. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | Change it to five | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA11 | Write to her. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HA15 | Email | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI02 | Go to calendar. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI06 | Put safari on the left and male on the right. | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "safari,male") |
| HI08 | Snap this window to the right. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI09 | Make the notes window full screen. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| HI10 | Center this window. | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "center") |
| HI11 | Make the male window bigger. | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI12 | Scroll after bit. | 1 | **unsafe** | model | direct scroll(direction=down) |
| HI14 | Press the archive button. | 1 | wrong | model | unsupported none |
| HI17 | Type C U soon. | 1 | **unsafe** | model | direct insert_text(text=C U soon) |
| HI18 | Change Monday to Tuesday | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| HI19 | Replace 2 PM with 230 PM. | 1 | **unsafe** | model | edit replace_text(new=230 PM; old=2 PM) |
| HI21 | Send an email to Marco that the meeting moved to 345. | 1 | **unsafe** | model | direct create_draft(content=Meeting moved to 345; recipient=Marco) |
| HI27 | Search mail for flight confirmation. | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI28 | What's on my calendar on Thursday? | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI30 | Sing the draft | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI31 | Review my reply. | 1 | wrong | model | clarification none “Please specify the email or message you want to review.” |

## context-benchmark.Tessa.p0.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 1 | 2/18 (11%) | 11 (10) | 5 | 0 |
| tag `negative` | 2/7 (29%) | 4 (4) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **10/18**. Clarification on cases where it is acceptable: 0/5 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 18/18 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 18 model calls): parseable JSON object 18/18 (100%), exact schema fields 18/18 (100%), passed strict validator 13/18 (72%); retries used: 0.

Latency per command (all routes): p50 555.5 ms, p95 763.2 ms, max 1069.2 ms (n=18). `model` p50 555.5 ms. Model call p50 555 ms, p95 763 ms (n=18). Warm-up request: 1476 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C02 | Switch to nit. | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "nit") |
| C03 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C04 | Reply to him saying sounds good. | 1 | **unsafe** | model | direct create_draft(content=sounds good; recipient=him) |
| C05 | Email them that Friday works. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C06 | Reply to that email saying it's paid. | 1 | **unsafe** | model | direct read_message(query=email) |
| C07 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C08 | Open it. | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C09 | Maximize it | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C10 | Put that window on the list. | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| C11 | Sengat | 1 | wrong | model | unsupported none |
| C12 | Reply to her. | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C13 | Change that to 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C16 | Change that to 4 p.m. | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C17 | Find her last email. | 1 | rejected | model | schemaViolation("“target” is empty") |
| C18 | Close it. | 1 | rejected | model | inconsistentIntent("direct requires an action") |

