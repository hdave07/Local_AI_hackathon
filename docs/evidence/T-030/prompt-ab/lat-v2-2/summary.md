# Intent benchmark (`--pipeline bonsai --prompt v2`)

Generated 2026-11-14T22:43:09Z by `flow-bench`, 1 runs per prompt, temperature 0, strict JSON schema.

## bonsai-benchmark.json — ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong (unsafe) | Rejected by validator | Transport error |
|---|---|---|---|---|
| intent (30) × 1 | 24/30 (80%) | 4 (4) | 2 | 0 |
| ambiguous (15) × 1 | 6/15 (40%) | 3 (3) | 6 | 0 |
| tag `draft-content` | 3/4 (75%) | 1 (1) | 0 | 0 |
| tag `email-search` | 4/4 (100%) | 0 (0) | 0 | 0 |

Unsafe guesses (validated action outside the accept set): **7/45**. Clarification on cases where it is acceptable: 2/15 (13%). Clarification where a definite answer was expected (over-asking): 0.

Routes: model 45/45 (100%).

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 45 model calls): parseable JSON object 45/45 (100%), exact schema fields 45/45 (100%), passed strict validator 37/45 (82%); retries used: 0.

Latency per command (all routes): p50 350.3 ms, p95 417.6 ms, max 473.1 ms (n=45). `model` p50 350.3 ms. Model call p50 350 ms, p95 418 ms (n=45). Warm-up request: 314 ms.

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

