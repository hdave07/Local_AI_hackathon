# T-002 Bonsai benchmark

Generated 2026-11-14T21:31:34Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong action | Rejected by validator | Transport error |
|---|---|---|---|---|
| Intent (30) × 3 runs | 58/90 (64%) | 15 | 17 | 0 |
| Ambiguous (15) × 3 runs | 13/45 (29%) | 12 | 20 | 0 |
| tag `email-search` | 6/12 (50%) | 3 | 3 | 0 |
| tag `draft-content` | 9/12 (75%) | 3 | 0 | 0 |

Ambiguous answered with `clarification`: 0/45 (0%). Unsafe ambiguous (validated action outside the accept set): 12.

Consistency: 27/45 (60%) cases gave an identical result in every run; unstable: A01, A05, A06, A07, A09, A10, A11, A12, A13, A14, I14, I15, I16, I19, I22, I24, I29, I30.

JSON-schema conformance (first attempt, 135 model calls): parseable JSON object 135/135 (100%), exact schema fields 124/135 (92%), passed strict validator 98/135 (73%); retries used: 0.

Warm latency per model call: p50 456 ms, p95 522 ms, max 588 ms (n=135). Warm-up request: 1425 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (all runs):

| Case | Utterance | Run | Outcome | Got |
|---|---|---|---|---|
| A01 | open it | 1 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| A01 | open it | 2 | wrong | direct activate_app(app=Safari) |
| A01 | open it | 3 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| A02 | make it bigger | 1 | wrong | direct resize_window(change=wider; window=active) |
| A02 | make it bigger | 2 | wrong | direct resize_window(change=wider; window=active) |
| A02 | make it bigger | 3 | wrong | direct resize_window(change=wider; window=active) |
| A03 | move that over there | 1 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A03 | move that over there | 2 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A03 | move that over there | 3 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A04 | reply to her | 1 | rejected | inconsistentIntent("direct requires an action") |
| A04 | reply to her | 2 | rejected | inconsistentIntent("direct requires an action") |
| A04 | reply to her | 3 | rejected | inconsistentIntent("direct requires an action") |
| A05 | delete that | 1 | rejected | inconsistentIntent("direct requires an action") |
| A05 | delete that | 2 | rejected | inconsistentIntent("direct requires an action") |
| A06 | check my schedule | 2 | rejected | schemaViolation("“target” is empty") |
| A07 | open the thing from yesterday | 1 | wrong | direct query_calendar(time=yesterday) |
| A07 | open the thing from yesterday | 2 | rejected | inconsistentIntent("direct requires an action") |
| A07 | open the thing from yesterday | 3 | wrong | direct query_calendar(time=yesterday) |
| A09 | put them side by side | 1 | wrong | direct tile_windows(left=Mail; right=Calendar) |
| A09 | put them side by side | 2 | rejected | unsupportedTarget(action: "tile_windows", target: "(empty)") |
| A09 | put them side by side | 3 | wrong | direct tile_windows(left=Mail; right=Calendar) |
| A10 | change the time | 1 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| A10 | change the time | 2 | rejected | inconsistentIntent("direct requires an action") |
| A10 | change the time | 3 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| A11 | email sarah | 1 | wrong | direct request_send |
| A12 | close it | 1 | wrong | direct resize_window(change=narrower; window=active) |
| A13 | find that email | 1 | rejected | schemaViolation("“target” is empty") |
| A14 | make it more formal | 1 | rejected | inconsistentIntent("direct requires an action") |
| A14 | make it more formal | 2 | rejected | inconsistentIntent("direct requires an action") |
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
| I15 | click new message | 1 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I15 | click new message | 3 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I16 | focus the search field | 1 | rejected | schemaViolation("“target” is empty") |
| I16 | focus the search field | 3 | rejected | schemaViolation("“target” is empty") |
| I17 | type hello everyone | 1 | rejected | inconsistentIntent("direct requires an action") |
| I17 | type hello everyone | 2 | rejected | inconsistentIntent("direct requires an action") |
| I17 | type hello everyone | 3 | rejected | inconsistentIntent("direct requires an action") |
| I19 | replace tuesday with wednesday | 1 | rejected | schemaViolation("“target” is empty") |
| I19 | replace tuesday with wednesday | 2 | wrong | direct replace_text(new=wednesday; old=tomorrow) |
| I19 | replace tuesday with wednesday | 3 | rejected | schemaViolation("“target” is empty") |
| I21 | email john saying the report is ready | 1 | wrong | direct read_message(query=john) |
| I21 | email john saying the report is ready | 2 | wrong | direct read_message(query=john) |
| I21 | email john saying the report is ready | 3 | wrong | direct read_message(query=john) |
| I24 | find sarah's email about tomorrow | 1 | wrong | direct query_calendar(time=sarah) |
| I24 | find sarah's email about tomorrow | 2 | wrong | direct query_calendar(time=tomorrow 4 pm) |
| I24 | find sarah's email about tomorrow | 3 | wrong | direct query_calendar(time=sarah) |
| I26 | search my mail for the budget report | 1 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 2 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 3 | rejected | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 1 | rejected | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 3 | rejected | schemaViolation("“target” is empty") |
| I30 | send it | 1 | wrong | unsupported none |
| I30 | send it | 3 | wrong | unsupported none |

