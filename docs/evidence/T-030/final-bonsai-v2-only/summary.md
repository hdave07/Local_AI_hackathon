# Intent benchmark (`--pipeline bonsai --prompt v2`)

Generated 2026-11-15T00:32:27Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 3 | 72/90 (80%) | 12 (12) | 6 | 0 |
| ambiguous (15) × 3 | 18/45 (40%) | 9 (9) | 18 | 0 |
| tag `draft-content` | 9/12 (75%) | 3 (3) | 0 | 0 |
| tag `email-search` | 12/12 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **21/135**. Clarification on cases where it is acceptable: 6/45 (13%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 135/135 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 135 model calls): parseable JSON object 135/135 (100%), exact schema fields 135/135 (100%), passed strict validator 111/135 (82%); retries used: 0.

Latency per command (all routes): p50 342.8 ms, p95 1263.0 ms, max 1342.5 ms (n=135). `model` p50 342.8 ms. Model call p50 343 ms, p95 1263 ms (n=135). Warm-up request: 322 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A02 | make it bigger | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | move that over there | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A08 | do the usual | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A09 | put them side by side | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | change the time | 1 | rejected | model | schemaViolation("“target” is empty") |
| A11 | email sarah | 1 | **unsafe** | model | direct activate_app(app=Mail) |
| A13 | find that email | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | make it more formal | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | move mail | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| I09 | maximize the mail window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | make the calendar window smaller | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | scroll to the top | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | click new message | 1 | **unsafe** | model | direct activate_app(app=Notes) |
| I17 | type hello everyone | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I21 | email john saying the report is ready | 1 | **unsafe** | model | direct read_message(query=john report ready) |

## heldout-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (31) × 3 | 72/93 (77%) | 12 (6) | 9 | 0 |
| ambiguous (15) × 3 | 12/45 (27%) | 12 (12) | 21 | 0 |
| tag `calendar` | 6/6 (100%) | 0 (0) | 0 | 0 |
| tag `draft-content` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `email-search` | 12/12 (100%) | 0 (0) | 0 | 0 |
| tag `slots` | 15/15 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **18/138**. Clarification on cases where it is acceptable: 3/45 (7%). Clarification where a definite answer was expected (over-asking): 3.

Routes: model 138/138 (100%).

Consistency: 46/46 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 138 model calls): parseable JSON object 138/138 (100%), exact schema fields 138/138 (100%), passed strict validator 108/138 (78%); retries used: 0.

Latency per command (all routes): p50 469.3 ms, p95 1597.1 ms, max 2011.2 ms (n=138). `model` p50 469.3 ms. Model call p50 469 ms, p95 1597 ms (n=138). Warm-up request: 322 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| HA01 | open that | 1 | **unsafe** | model | direct activate_app(app=Finder) |
| HA03 | move it | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| HA05 | send it to him | 1 | **unsafe** | model | direct request_send |
| HA06 | remove this | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA07 | check the time | 1 | rejected | model | schemaViolation("“target” is empty") |
| HA08 | find it | 1 | rejected | model | schemaViolation("“target” is empty") |
| HA09 | put those two next to each other | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| HA10 | change it to 5 | 1 | rejected | model | schemaViolation("“detail” is empty") |
| HA11 | write to her | 1 | **unsafe** | model | direct create_draft(content=; recipient=her) |
| HA13 | do that again | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HA14 | make this sound nicer | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| HI02 | go to calendar | 1 | rejected | model | schemaViolation("“target” is empty") |
| HI08 | snap this window to the right | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| HI09 | make the notes window full screen | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "full screen") |
| HI10 | center this window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "center") |
| HI11 | make the mail window bigger | 1 | **unsafe** | model | direct resize_window(change=wider; window=Mail) |
| HI14 | press the archive button | 1 | wrong | model | unsupported none |
| HI17 | type see you soon | 1 | wrong | model | clarification none “Which app should I open?” |

## context-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| contextual (18) × 3 | 21/54 (39%) | 27 (18) | 6 | 0 |
| tag `negative` | 18/21 (86%) | 3 (3) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **18/54**. Clarification on cases where it is acceptable: 9/15 (60%). Clarification where a definite answer was expected (over-asking): 9.

Routes: model 54/54 (100%).

Consistency: 18/18 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 54 model calls): parseable JSON object 54/54 (100%), exact schema fields 54/54 (100%), passed strict validator 48/54 (89%); retries used: 0.

Latency per command (all routes): p50 413.0 ms, p95 1032.4 ms, max 2007.3 ms (n=54). `model` p50 413.0 ms. Model call p50 413 ms, p95 1032 ms (n=54). Warm-up request: 322 ms.

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| C01 | open it | 1 | wrong | model | clarification none “Which app should I open?” |
| C02 | switch to it | 1 | wrong | model | clarification none “Which app should I switch to?” |
| C03 | reply to her | 1 | wrong | model | clarification none “Which person should I reply to?” |
| C04 | reply to him saying sounds good | 1 | **unsafe** | model | direct create_draft(content=sounds good; recipient=him) |
| C05 | email them that friday works | 1 | rejected | model | schemaViolation("“target” is empty") |
| C06 | reply to that email saying it's paid | 1 | **unsafe** | model | direct create_draft(content=it's paid; recipient=email) |
| C09 | maximize it | 1 | **unsafe** | model | direct resize_window(change=larger; window=active) |
| C10 | put that window on the left | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "active") |
| C13 | change that to 4 pm | 1 | **unsafe** | model | edit replace_text(new=4:00; old=3) |
| C16 | change that to 4 pm | 1 | **unsafe** | model | edit replace_text(new=4:00; old=3) |
| C17 | find her last email | 1 | **unsafe** | model | direct read_message(query=her last email) |

