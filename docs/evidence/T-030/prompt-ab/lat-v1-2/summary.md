# Intent benchmark (`--pipeline bonsai --prompt v1`)

Generated 2026-11-14T22:42:47Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 21/30 (70%) | 7 (7) | 2 | 0 |
| ambiguous (15) × 1 | 5/15 (33%) | 4 (4) | 6 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **11/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 37/45 (82%); retries used: 0.

Latency per command (all routes): p50 459.8 ms, p95 515.7 ms, max 553.3 ms (n=45). `model` p50 459.8 ms. Model call p50 460 ms, p95 516 ms (n=45). Warm-up request: 437 ms.

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

