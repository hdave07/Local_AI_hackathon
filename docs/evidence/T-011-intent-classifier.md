# T-011 evidence — Bonsai intent classifier via LM Studio

**Date:** 2026-11-14 · **Machine:** Apple Silicon, 8 GB RAM, macOS 26.6.2 (25G83), Xcode 27.1, Swift 6.4
**Runtime:** LM Studio OpenAI-compatible server at `http://localhost:1234/v1`, model `ternary-bonsai-2-2b-mlx`
**Request:** `POST /v1/chat/completions`, `temperature: 0`, `response_format: {type: json_schema, strict: true}`

## Reproduce
```
swift test                       # unit tests, no server needed
FLOW_LIVE_LLM=1 swift test       # also runs live tests against LM Studio
scripts/build_app.sh --open      # build and launch build/Flow.app
```

## Live results (final prompt, single run)
| Utterance | Validated result | Latency |
|---|---|---|
| open notes | activate_app → Notes | 3.19 s |
| open mail | activate_app → Mail | 2.65 s |
| put mail and calendar side by side | tile_windows → Mail, Calendar | 3.16 s |
| scroll down | scroll → down | 2.61 s |
| send it | request_send (risk external) | 2.89 s |
| make this window a little wider | resize_window → active, wider | 2.90 s |
| change 3 to 3:30 | replace_text "3" → "3:30" (edit) | 3.25 s |
| reply to sarah that I can meet tomorrow | create_draft → sarah, content "" (content dropped) | 2.95 s |
| do I have anything at four tomorrow | query_calendar → "tomorrow 4 pm" | 3.23 s |
| find sarah's email about tomorrow | **query_calendar → "sarah" (wrong; expected read_message)** | 2.93 s |
| order me a pizza | unsupported, no action | 2.61 s |
| open terminal and delete my files | **rejected**: unsupportedTarget(activate_app, terminal) | 2.93 s |
| (model ID `no-such-model`) | **rejected**: modelMismatch | 2.68 s |
| (closed port 1299) | **rejected**: serverUnavailable | 0.07 s |

Cold first request after model idle: ~16.6 s (observed twice).

## Observations
- LM Studio answered a request for a non-existent model ID with the loaded model (HTTP 200). The client now rejects any response whose `model` differs from the requested ID.
- Output varies across runs at `temperature: 0` (create_draft content was "I can meet tomorrow" in one run, "" in another).
- Adding one `read_message` few-shot example fixed that case but broke `open notes` (empty target) and `send it` (unsupported). The change was reverted; prompt tuning needs the T-002 benchmark set, not ad-hoc examples.
- The bundled app (ATS `NSAllowsLocalNetworking`) reached `GET /v1/models` at launch (LM Studio server log, 16:04:12).
