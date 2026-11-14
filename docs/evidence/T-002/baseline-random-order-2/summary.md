# T-002 Bonsai benchmark

Generated 2026-11-14T21:33:50Z by `flow-bench`, 3 runs per prompt, temperature 0, strict JSON schema.

## ternary-bonsai-2-2b-mlx

| Set | Pass | Wrong action | Rejected by validator | Transport error |
|---|---|---|---|---|
| Intent (30) × 3 runs | 35/90 (39%) | 21 | 34 | 0 |
| Ambiguous (15) × 3 runs | 3/45 (7%) | 9 | 33 | 0 |
| tag `email-search` | 3/12 (25%) | 3 | 6 | 0 |
| tag `draft-content` | 0/12 (0%) | 9 | 3 | 0 |

Ambiguous answered with `clarification`: 0/45 (0%). Unsafe ambiguous (validated action outside the accept set): 9.

Consistency: 43/45 (96%) cases gave an identical result in every run; unstable: I01, I03.

JSON-schema conformance (first attempt, 135 model calls): parseable JSON object 135/135 (100%), exact schema fields 135/135 (100%), passed strict validator 68/135 (50%); retries used: 0.

Warm latency per model call: p50 442 ms, p95 515 ms, max 549 ms (n=135). Warm-up request: 2300 ms.

Malformed model outputs rejected with the expected error: 10/10 (100%).

Non-passing results (all runs):

| Case | Utterance | Run | Outcome | Got |
|---|---|---|---|---|
| A01 | open it | 1 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| A01 | open it | 2 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
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
| A05 | delete that | 3 | rejected | inconsistentIntent("direct requires an action") |
| A06 | check my schedule | 1 | rejected | schemaViolation("“target” is empty") |
| A06 | check my schedule | 2 | rejected | schemaViolation("“target” is empty") |
| A06 | check my schedule | 3 | rejected | schemaViolation("“target” is empty") |
| A07 | open the thing from yesterday | 1 | rejected | inconsistentIntent("direct requires an action") |
| A07 | open the thing from yesterday | 2 | rejected | inconsistentIntent("direct requires an action") |
| A07 | open the thing from yesterday | 3 | rejected | inconsistentIntent("direct requires an action") |
| A09 | put them side by side | 1 | rejected | unsupportedTarget(action: "tile_windows", target: "(empty)") |
| A09 | put them side by side | 2 | rejected | unsupportedTarget(action: "tile_windows", target: "(empty)") |
| A09 | put them side by side | 3 | rejected | unsupportedTarget(action: "tile_windows", target: "(empty)") |
| A10 | change the time | 1 | wrong | unsupported none |
| A10 | change the time | 2 | wrong | unsupported none |
| A10 | change the time | 3 | wrong | unsupported none |
| A11 | email sarah | 1 | wrong | direct request_send |
| A11 | email sarah | 2 | wrong | direct request_send |
| A11 | email sarah | 3 | wrong | direct request_send |
| A12 | close it | 1 | rejected | inconsistentIntent("direct requires an action") |
| A12 | close it | 2 | rejected | inconsistentIntent("direct requires an action") |
| A12 | close it | 3 | rejected | inconsistentIntent("direct requires an action") |
| A13 | find that email | 1 | rejected | schemaViolation("“target” is empty") |
| A13 | find that email | 2 | rejected | schemaViolation("“target” is empty") |
| A13 | find that email | 3 | rejected | schemaViolation("“target” is empty") |
| A14 | make it more formal | 1 | rejected | inconsistentIntent("direct requires an action") |
| A14 | make it more formal | 2 | rejected | inconsistentIntent("direct requires an action") |
| A14 | make it more formal | 3 | rejected | inconsistentIntent("direct requires an action") |
| A15 | move mail | 1 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A15 | move mail | 2 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| A15 | move mail | 3 | rejected | unsupportedTarget(action: "move_window", target: "(empty)") |
| I01 | open notes | 2 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I01 | open notes | 3 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I03 | launch calendar | 2 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I03 | launch calendar | 3 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I09 | maximize the mail window | 1 | rejected | unsupportedTarget(action: "resize_window", target: "(empty)") |
| I09 | maximize the mail window | 2 | rejected | unsupportedTarget(action: "resize_window", target: "(empty)") |
| I09 | maximize the mail window | 3 | rejected | unsupportedTarget(action: "resize_window", target: "(empty)") |
| I11 | make the calendar window smaller | 1 | wrong | direct resize_window(change=narrower; window=active) |
| I11 | make the calendar window smaller | 2 | wrong | direct resize_window(change=narrower; window=active) |
| I11 | make the calendar window smaller | 3 | wrong | direct resize_window(change=narrower; window=active) |
| I13 | scroll to the top | 1 | wrong | direct scroll(direction=up) |
| I13 | scroll to the top | 2 | wrong | direct scroll(direction=up) |
| I13 | scroll to the top | 3 | wrong | direct scroll(direction=up) |
| I14 | click the reply button | 1 | rejected | schemaViolation("“target” is empty") |
| I14 | click the reply button | 2 | rejected | schemaViolation("“target” is empty") |
| I14 | click the reply button | 3 | rejected | schemaViolation("“target” is empty") |
| I15 | click new message | 1 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I15 | click new message | 2 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I15 | click new message | 3 | rejected | unsupportedTarget(action: "activate_app", target: "(empty)") |
| I16 | focus the search field | 1 | rejected | schemaViolation("“target” is empty") |
| I16 | focus the search field | 2 | rejected | schemaViolation("“target” is empty") |
| I16 | focus the search field | 3 | rejected | schemaViolation("“target” is empty") |
| I17 | type hello everyone | 1 | rejected | inconsistentIntent("direct requires an action") |
| I17 | type hello everyone | 2 | rejected | inconsistentIntent("direct requires an action") |
| I17 | type hello everyone | 3 | rejected | inconsistentIntent("direct requires an action") |
| I19 | replace tuesday with wednesday | 1 | rejected | schemaViolation("“target” is empty") |
| I19 | replace tuesday with wednesday | 2 | rejected | schemaViolation("“target” is empty") |
| I19 | replace tuesday with wednesday | 3 | rejected | schemaViolation("“target” is empty") |
| I20 | reply to sarah that I can meet tomorrow | 1 | wrong | direct create_draft(content=; recipient=sarah) |
| I20 | reply to sarah that I can meet tomorrow | 2 | wrong | direct create_draft(content=; recipient=sarah) |
| I20 | reply to sarah that I can meet tomorrow | 3 | wrong | direct create_draft(content=; recipient=sarah) |
| I21 | email john saying the report is ready | 1 | rejected | schemaViolation("“target” is empty") |
| I21 | email john saying the report is ready | 2 | rejected | schemaViolation("“target” is empty") |
| I21 | email john saying the report is ready | 3 | rejected | schemaViolation("“target” is empty") |
| I22 | write to alex and ask if friday works | 1 | wrong | direct create_draft(content=; recipient=alex) |
| I22 | write to alex and ask if friday works | 2 | wrong | direct create_draft(content=; recipient=alex) |
| I22 | write to alex and ask if friday works | 3 | wrong | direct create_draft(content=; recipient=alex) |
| I23 | reply to sarah: thanks, see you at four | 1 | wrong | direct create_draft(content=; recipient=sarah) |
| I23 | reply to sarah: thanks, see you at four | 2 | wrong | direct create_draft(content=; recipient=sarah) |
| I23 | reply to sarah: thanks, see you at four | 3 | wrong | direct create_draft(content=; recipient=sarah) |
| I24 | find sarah's email about tomorrow | 1 | wrong | direct query_calendar(time=sarah) |
| I24 | find sarah's email about tomorrow | 2 | wrong | direct query_calendar(time=sarah) |
| I24 | find sarah's email about tomorrow | 3 | wrong | direct query_calendar(time=sarah) |
| I26 | search my mail for the budget report | 1 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 2 | rejected | schemaViolation("“target” is empty") |
| I26 | search my mail for the budget report | 3 | rejected | schemaViolation("“target” is empty") |
| I27 | show me the email from alex about the offsite | 1 | rejected | schemaViolation("“target” is empty") |
| I27 | show me the email from alex about the offsite | 2 | rejected | schemaViolation("“target” is empty") |
| I27 | show me the email from alex about the offsite | 3 | rejected | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 1 | rejected | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 2 | rejected | schemaViolation("“target” is empty") |
| I29 | am I free on friday afternoon | 3 | rejected | schemaViolation("“target” is empty") |
| I30 | send it | 1 | wrong | unsupported none |
| I30 | send it | 2 | wrong | unsupported none |
| I30 | send it | 3 | wrong | unsupported none |

