# Intent benchmark (`--pipeline bonsai --prompt v3`)

Generated 2026-11-14T22:40:44Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 22/30 (73%) | 5 (5) | 3 | 0 |
| ambiguous (15) × 1 | 3/15 (20%) | 5 (5) | 7 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 2/4 (50%) | 1 (1) | 1 | 0 |

Unsafe guesses (validated action outside the accept set): **10/45**. Clarification on cases where it is acceptable: 0/15 (0%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 35/45 (78%); retries used: 0.

Latency per command (all routes): p50 538.4 ms, p95 599.3 ms, max 602.3 ms (n=45). `model` p50 538.4 ms. Model call p50 538 ms, p95 599 ms (n=45). Warm-up request: 1499 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (run 1, plus every run of unstable cases):

| Case | Utterance | Run | Outcome | Route | Got |
|---|---|---|---|---|---|
| A01 | open it | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| A02 | make it bigger | 1 | **unsafe** | model | direct resize_window(change=wider; window=active) |
| A03 | move that over there | 1 | rejected | model | unsupportedTarget(action: "move_window", target: "(empty)") |
| A05 | delete that | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A07 | open the thing from yesterday | 1 | **unsafe** | model | direct query_calendar(time=yesterday) |
| A09 | put them side by side | 1 | **unsafe** | model | direct tile_windows(left=Mail; right=Calendar) |
| A10 | change the time | 1 | rejected | model | schemaViolation("“target” is empty") |
| A11 | email sarah | 1 | **unsafe** | model | direct read_message(query=sarah) |
| A12 | close it | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A13 | find that email | 1 | rejected | model | schemaViolation("“target” is empty") |
| A14 | make it more formal | 1 | rejected | model | inconsistentIntent("direct requires an action") |
| A15 | move mail | 1 | rejected | model | unsupportedTarget(action: "tile_windows", target: "mail") |
| I09 | maximize the mail window | 1 | rejected | model | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | make the calendar window smaller | 1 | **unsafe** | model | direct resize_window(change=narrower; window=active) |
| I13 | scroll to the top | 1 | **unsafe** | model | direct scroll(direction=up) |
| I15 | click new message | 1 | **unsafe** | model | direct activate_app(app=Safari) |
| I17 | type hello everyone | 1 | rejected | model | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I21 | email john saying the report is ready | 1 | **unsafe** | model | direct read_message(query=john) |
| I24 | find sarah's email about tomorrow | 1 | **unsafe** | model | direct query_calendar(time=tomorrow) |
| I26 | search my mail for the budget report | 1 | rejected | model | schemaViolation("“target” is empty") |

