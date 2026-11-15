# Intent benchmark (`--pipeline bonsai`)

Generated 2026-11-14T22:27:04Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 3 | 63/90 (70%) | 21 (21) | 6 | 0 |
| ambiguous (15) × 3 | 15/45 (33%) | 12 (12) | 18 | 0 |
| tag `draft-content` | 9/12 (75%) | 3 (3) | 0 | 0 |
| tag `email-search` | 6/12 (50%) | 3 (3) | 3 | 0 |

Unsafe guesses (validated action outside the accept set): **33/135**. Clarification on cases where it is acceptable: 0/45 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 135/135 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 135 model calls): parseable JSON object 135/135 (100%), exact schema fields 135/135 (100%), passed strict validator 111/135 (82%); retries used: 0.

Latency per command (all routes): p50 449.6 ms, p95 508.0 ms, max 547.6 ms (n=135). `model` p50 449.6 ms. Model call p50 450 ms, p95 508 ms (n=135). Warm-up request: 710 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | open it | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | make it bigger | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | move that over there | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A07 | open the thing from yesterday | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | put them side by side | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | change the time | 1 | rejected | model | schemaViolation("“target” is empty") |
| A12 | close it | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A13 | find that email | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | make it more formal | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | move mail | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I09 | maximize the mail window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | make the calendar window smaller | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | scroll to the top | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | click new message | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| I17 | type hello everyone | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| I21 | email john saying the report is ready | 1 | **unsafe** | model | direct read_message(query=john) |
| I24 | find sarah's email about tomorrow | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| I26 | search my mail for the budget report | 1 | rejected | model | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |

## heldout-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 3 | 57/93 (61%) | 21 (15) | 15 | 0 |
| ambiguous (15) × 3 | 9/45 (20%) | 12 (9) | 24 | 0 |
| tag `calendar` | 3/6 (50%) | 3 (3) | 0 | 0 |
| tag `draft-content` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 6/12 (50%) | 0 (0) | 6 | 0 |
| tag `slots` | 12/15 (80%) | 3 (3) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **24/138**. Clarification on cases where it is acceptable: 0/45 (0%). Clarification where a definite answer was expected (over-asking): 3.

Routes: model 138/138 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 138 model calls): parseable JSON object 138/138 (100%), exact schema fields 138/138 (100%), passed strict validator 99/138 (72%); retries used: 0.

Latency per command (all routes): p50 450.6 ms, p95 582.7 ms, max 640.2 ms (n=138). `model` p50 450.6 ms. Model call p50 451 ms, p95 583 ms (n=138). Warm-up request: 710 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | open that | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| HA03 | move it | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA04 | reply | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA05 | send it to him | 1 | **unsafe** | model | direct request_send |
| HA06 | remove this | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA08 | find it | 1 | wrong | model | unsupported none |
| HA09 | put those two next to each other | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | change it to 5 | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA11 | write to her | 1 | rejected | model | schemaViolation("“target” is empty") |
| HA12 | shut it | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA14 | make this sound nicer | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA15 | email | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI02 | go to calendar | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI08 | snap this window to the right | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI09 | make the notes window full screen | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| HI10 | center this window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "center") |
| HI11 | make the mail window bigger | 1 | **unsafe** | model | direct resize_window(change=wider; window=Mail) |
| HI14 | press the archive button | 1 | wrong | model | unsupported none |
| HI17 | type see you soon | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HI18 | change monday to tuesday | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| HI25 | find the message from marco | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI27 | search mail for flight confirmation | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI28 | what's on my calendar on thursday | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| HI31 | review my reply | 1 | wrong | model | clarification none “Please specify the draft or email to review.” |

## context-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 3 | 9/54 (17%) | 27 (24) | 18 | 0 |
| tag `negative` | 6/21 (29%) | 12 (12) | 3 | 0 |

Unsafe guesses (validated action outside the accept set): **24/54**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 54/54 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 54 model calls): parseable JSON object 54/54 (100%), exact schema fields 54/54 (100%), passed strict validator 36/54 (67%); retries used: 0.

Latency per command (all routes): p50 465.5 ms, p95 536.2 ms, max 566.1 ms (n=54). `model` p50 465.5 ms. Model call p50 466 ms, p95 536 ms (n=54). Warm-up request: 710 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | open it | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C02 | switch to it | 1 | wrong | model | unsupported none |
| C03 | reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C04 | reply to him saying sounds good | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| C05 | email them that friday works | 1 | rejected | model | schemaViolation("“target” is empty") |
| C06 | reply to that email saying it's paid | 1 | **unsafe** | model | direct read_message(query=email subject or sender indicating payment) |
| C07 | reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C08 | open it | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| C09 | maximize it | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| C10 | put that window on the left | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "active") |
| C12 | reply to her | 1 | **unsafe** | model | task create_draft(content=; recipient=her) |
| C13 | change that to 4 pm | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C16 | change that to 4 pm | 1 | **unsafe** | model | direct query_calendar(time=tomorrow 4 pm) |
| C17 | find her last email | 1 | rejected | model | schemaViolation("“target” is empty") |
| C18 | close it | 1 | rejected | model | inconsistentIntent("direct requires an action") |

