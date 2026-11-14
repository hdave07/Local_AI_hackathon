# T-002 Bonsai benchmark

Generated 2026-11-14T21:39:13Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong action | Rejected by validator | Transport error |
|---|---|---|---|---|
| Intent (30) × 3 runs | 66/90 (73%) | 18 | 6 | 0 |
| Ambiguous (15) × 3 runs | 21/45 (47%) | 21 | 3 | 0 |
| tag `email-search` | 6/12 (50%) | 3 | 3 | 0 |
| tag `draft-content` | 9/12 (75%) | 3 | 0 | 0 |

Ambiguous answered with `clarification`: 0/45 (0%). Unsafe ambiguous (validated action outside the accept set): 21.

Consistency: 45/45 (100%) cases gave an identical result in every run.

JSON-schema conformance (first attempt, 135 model calls): parseable JSON object 135/135 (100%), exact schema fields 135/135 (100%), passed strict validator 126/135 (93%); retries used: 0.

Warm latency per model call: p50 499 ms, p95 583 ms, max 652 ms (n=135). Warm-up request: 598 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (all runs):

| Case | Utterance | Run | Outcome | Got |
|---|---|---|---|---|
| A01 | open it | 1 | wrong | direct activate_app(app=Safari) |
| A01 | open it | 2 | wrong | direct activate_app(app=Safari) |
| A01 | open it | 3 | wrong | direct activate_app(app=Safari) |
| A02 | make it bigger | 1 | wrong | direct resize_window(change=wider; window=active) |
| A02 | make it bigger | 2 | wrong | direct resize_window(change=wider; window=active) |
| A02 | make it bigger | 3 | wrong | direct resize_window(change=wider; window=active) |
| A03 | move that over there | 1 | wrong | direct move_window(position=left_half; window=active) |
| A03 | move that over there | 2 | wrong | direct move_window(position=left_half; window=active) |
| A03 | move that over there | 3 | wrong | direct move_window(position=left_half; window=active) |
| A04 | reply to her | 1 | wrong | unsupported none |
| A04 | reply to her | 2 | wrong | unsupported none |
| A04 | reply to her | 3 | wrong | unsupported none |
| A07 | open the thing from yesterday | 1 | wrong | direct query_calendar(time=yesterday) |
| A07 | open the thing from yesterday | 2 | wrong | direct query_calendar(time=yesterday) |
| A07 | open the thing from yesterday | 3 | wrong | direct query_calendar(time=yesterday) |
| A09 | put them side by side | 1 | wrong | direct tile_windows(left=Mail; right=Calendar) |
| A09 | put them side by side | 2 | wrong | direct tile_windows(left=Mail; right=Calendar) |
| A09 | put them side by side | 3 | wrong | direct tile_windows(left=Mail; right=Calendar) |
| A10 | change the time | 1 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| A10 | change the time | 2 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| A10 | change the time | 3 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| A15 | move mail | 1 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A15 | move mail | 2 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A15 | move mail | 3 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| I09 | maximize the mail window | 1 | rejected | unsupportedTarget(action: "resize_window", target: "maximize") |
| I09 | maximize the mail window | 2 | rejected | unsupportedTarget(action: "resize_window", target: "maximize") |
| I09 | maximize the mail window | 3 | rejected | unsupportedTarget(action: "resize_window", target: "maximize") |
| I11 | make the calendar window smaller | 1 | wrong | direct resize_window(change=narrower; window=active) |
| I11 | make the calendar window smaller | 2 | wrong | direct resize_window(change=narrower; window=active) |
| I11 | make the calendar window smaller | 3 | wrong | direct resize_window(change=narrower; window=active) |
| I13 | scroll to the top | 1 | wrong | direct scroll(direction=up) |
| I13 | scroll to the top | 2 | wrong | direct scroll(direction=up) |
| I13 | scroll to the top | 3 | wrong | direct scroll(direction=up) |
| I17 | type hello everyone | 1 | wrong | unsupported none |
| I17 | type hello everyone | 2 | wrong | unsupported none |
| I17 | type hello everyone | 3 | wrong | unsupported none |
| I19 | replace tuesday with wednesday | 1 | wrong | direct replace_text(new=wednesday; old=tomorrow) |
| I19 | replace tuesday with wednesday | 2 | wrong | direct replace_text(new=wednesday; old=tomorrow) |
| I19 | replace tuesday with wednesday | 3 | wrong | direct replace_text(new=wednesday; old=tomorrow) |
| I21 | email john saying the report is ready | 1 | wrong | direct read_message(query=john) |
| I21 | email john saying the report is ready | 2 | wrong | direct read_message(query=john) |
| I21 | email john saying the report is ready | 3 | wrong | direct read_message(query=john) |
| I24 | find sarah's email about tomorrow | 1 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| I24 | find sarah's email about tomorrow | 2 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| I24 | find sarah's email about tomorrow | 3 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| I26 | search my mail for the budget report | 1 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 2 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 3 | rejected | schemaViolation("“target” is empty") |

