# Flow | Hands-Free Mac

### Your computer. Your voice. Your workflow.

**Flow is a local-first, voice-driven macOS accessibility assistant that helps people with limited hand or upper-limb mobility complete everyday tasks through natural conversation.**

Traditional voice controls often require users to issue individual commands to navigate their computers. Flow takes a more task-oriented approach, allowing users to move between applications, ask questions, make corrections, and continue what they were doing without constantly returning to the keyboard or mouse.

By combining local AI with native macOS accessibility APIs, Flow translates natural-language instructions into bounded, verifiable actions.

**One conversation. Multiple applications. More independence.**

## Meet Flow

Imagine you need to respond to an email about scheduling a meeting.

Instead of manually opening applications, searching through messages, checking your calendar, and editing a reply, you can simply talk to Flow.

> **You:** "Find Sarah's email about tomorrow."
>
> **Flow:** "I found two messages from Sarah. Which one?"
>
> **You:** "The second one."
>
> **You:** "Do I have anything at four tomorrow?"
>
> **Flow:** "You have a tentative meeting at four."
>
> **You:** "Reply saying I can meet at four."
>
> **You:** "Actually, change four to four thirty."
>
> **You:** "Read my reply."

Flow is designed to make these connected actions feel like one interaction.

It maintains relevant task context, asks clarifying questions when necessary, and checks supported actions against the actual application state rather than assuming they succeeded.

The goal is not simply to control a computer with voice commands. It is to make completing a task feel natural, even when that task involves multiple applications and corrections along the way.

*This example illustrates Flow's intended integrated workflow. Some Mail editing and sending operations require additional live verification before unrestricted use.*

## Features

### Natural, conversational control

Flow understands everyday instructions and supports follow-up questions and corrections.

Instead of repeatedly specifying the application, window, or target, users can respond with phrases such as:

- "The first one."
- "What about tomorrow?"
- "Actually, make that four thirty."
- "Read it back to me."
- "Never mind."

Flow combines deterministic command routing with local language understanding to interpret supported requests while preserving relevant conversational context.

### Application and window management

Control your workspace without manually arranging windows.

Flow supports opening and switching applications, moving and resizing windows, tiling windows side by side, minimizing and restoring windows, and returning to previously used applications.

Examples include:

- "Open Notes."
- "Bring Calendar to the front."
- "Put Mail on the left."
- "Minimize this window."
- "Restore it."
- "Go back to Notes."
- "Show me my open windows."

Window actions use native macOS Accessibility APIs and are verified against actual window state.

### Interface navigation

Flow can interact with accessible controls in supported macOS applications.

It can inspect interface elements, identify available actions, focus controls, click buttons, and scroll through content.

When several controls match a request, Flow can display numbered choices and ask the user which one they intended.

This allows users to navigate beyond a fixed set of application-specific commands, although coverage depends on the accessibility information exposed by each application.

### Email assistance

Flow integrates with Apple Mail to support conversational email workflows.

Its Mail functionality includes:

- Searching for messages by sender or other supported criteria.
- Resolving ambiguous results when multiple messages match.
- Opening and reading selected messages.
- Creating replies in native Apple Mail compose windows.
- Reviewing draft content.
- Performing targeted draft edits through its text-editing integration.
- Requiring explicit approval before any permitted send operation.

Flow is designed to preserve the correct recipient, message thread, and draft state throughout these interactions.

**Current limitation:** The live executor restricts Mail access to the synthetic `FlowTest` mailbox. Real Mail draft editing is disabled by default pending live verification. Real sending is also disabled by default, with a separate dry-run mode for testing its safety and confirmation flow.

### Calendar awareness

Flow uses Apple's EventKit framework to answer questions about authorized calendar events.

Users can ask:

- "What's on my calendar tomorrow?"
- "Do I have anything at four?"
- "Am I free Friday afternoon?"
- "What about tomorrow?"
- "Show me tomorrow in Calendar."

Flow distinguishes busy, tentative, free within the checked calendars, and unknown availability.

Calendar queries can be continued conversationally without restarting the entire request.

By default, Flow reads only the synthetic `FlowTest` calendar. Broader calendar access requires explicit configuration and authorization.

### Voice-driven text editing

Flow includes a deterministic text-editing engine designed for precise, reversible changes.

Supported editing operations include appending text, replacing specific phrases, removing text, reviewing content, and undoing compatible changes.

Instead of rewriting an entire message to correct one detail, a user can request a targeted change such as:

> "Change three thirty to four."

The editing engine tracks versions and checks for unexpected modifications to avoid silently overwriting newer content.

Actual application-level editing depends on the supported editor and integration.

### A floating assistant that stays with you

Flow includes a compact floating heads-up display (HUD) that remains visible while users work in other applications.

The HUD communicates:

- Whether Flow is listening, processing, speaking, or waiting.
- What the user said.
- The current question or clarification.
- Numbered options when a choice is required.
- The outcome of a supported action.
- What the user can say next.

The panel does not normally take keyboard focus away from the active application.

Users can reposition it, collapse it into a smaller status indicator, or hide it until another question requires their attention.

### Spoken feedback

Flow uses local macOS text-to-speech to communicate important information.

It can speak clarifying questions, read back content, explain failures, and request confirmation for consequential actions.

Routine actions can remain quiet to avoid overwhelming the user with unnecessary narration.

Stop and cancellation commands are handled separately from ordinary model-based requests to keep interruption responsive.

### Safety and user control

Flow is designed around the principle that the user remains in control of consequential actions.

Its execution architecture includes:

- A finite allowlist of supported actions.
- Bounded multi-step plans.
- Verification against live application state.
- Clarification when important targets are ambiguous.
- Cancellation and interruption handling.
- Version-bound confirmation for sensitive actions.
- Protection against accidentally repeating a send.
- Refusal to silently perform unsupported or destructive operations.

The language model interprets requests but does not directly execute arbitrary system commands.

## How Flow Works

Flow combines local speech recognition, language understanding, deterministic planning, and native macOS execution.

```text
                  User speaks
                       |
                       v
               Argmax Pro SDK
              Speech recognition
                       |
                       v
                  FlowRouting
           Deterministic commands
             and conversational
                   context
                       |
             +---------+---------+
             |                   |
             v                   v
       Direct action      Bonsai 2 via
                          LM Studio
                          Local intent
                         understanding
             |                   |
             +---------+---------+
                       |
                       v
                  FlowPlanner
             Validated, bounded
                   actions
                       |
                       v
                 FlowExecutor
              Native macOS APIs
                       |
                       v
               Verified outcome
                       |
             +---------+---------+
             |                   |
             v                   v
        Floating HUD       Spoken feedback
```

### Technology Stack

| Component | Technology |
| --- | --- |
| Application | Swift, SwiftUI, AppKit |
| Speech recognition | Argmax Pro SDK 3.1.8 |
| Language model | Bonsai 2 |
| Local inference | LM Studio |
| Application control | macOS Accessibility APIs |
| Calendar | EventKit |
| Mail integration | Apple Mail scripting and Accessibility |
| Speech output | Native macOS text-to-speech |
| Build system | Swift Package Manager |

### Local-first architecture

Flow's core speech recognition and language understanding run locally.

It uses Argmax Pro for speech transcription, Bonsai 2 for supported natural-language interpretation, and LM Studio as the local model server.

Native macOS APIs execute supported actions on the computer itself.

The core assistant does not require a cloud-hosted language model. However, applications such as Mail and Safari may still use network connections for their normal services.

## Project Status

Flow is a hackathon prototype focused on making supported macOS workflows more accessible through natural conversation.

The project includes implemented components for speech recognition, local language understanding, window control, interface navigation, Mail and Calendar integration, text editing, task planning, a persistent HUD, and spoken feedback.

Some components have been verified through live application tests, while other integrations currently rely on simulated tests or require explicit opt-in configuration.

Flow is not intended to replace the complete functionality of built-in macOS accessibility tools, and it does not guarantee support for every application or interface.

For implementation evidence and current limitations, see [docs/evidence](docs/evidence) and [docs/adr](docs/adr).

## Documentation

- [Product Requirements](docs/01_Flow_Unified_PRD.md)
- [Technical Specification](docs/02_Flow_Technical_Behavioral_Spec.md)
- [Implementation Plan](docs/03_Flow_Agent_Implementation_Plan.md)

## Development

### Requirements

- macOS
- Xcode 27+ and Swift 6.4
- LM Studio local server at `http://localhost:1234/v1`
- The `ternary-bonsai-2-2b-mlx` model loaded in LM Studio
- Argmax SDK registry access for speech recognition
- Required macOS microphone, Accessibility, Calendar, and Apple Events permissions for applicable features

### Build and test

```bash
swift build
swift test
```

### Live integration tests

```bash
# Live tests against the local LM Studio server
FLOW_LIVE_LLM=1 swift test

# Live window tests
# Moves your real Notes window, then restores it
FLOW_LIVE_AX=1 swift test

# Build and launch Flow.app
scripts/build_app.sh --open
```

### Window control through flowctl

```bash
.build/debug/flowctl \
  "activate notes" \
  "move notes left_half" \
  "undo"
```

### UI navigation through flowctl

```bash
.build/debug/flowctl \
  "click seven in Calculator" \
  "show numbers in Calculator" \
  "choose 25"
```

### Navigation integration tests

```bash
swift build --product flow-nav-fixture

FLOW_LIVE_AX=1 swift test --filter FlowAXTests
```

### Mail testing

```bash
.build/debug/flowctl \
  "mail find mail from sarah in mailbox FlowTest" \
  "mail choose 2" \
  "mail read it"
```

To run the live Mail tests, first import `fixtures/mail/FlowTest.mbox` into Apple Mail.

```bash
FLOW_LIVE_MAIL=1 swift test --filter FlowMailTests
```

These tests can interact with native Mail. Review the relevant test scopes before enabling live integrations.

### Calendar testing

Import `fixtures/calendar/FlowTest.ics` into Apple Calendar, then run:

```bash
scripts/run_calendar_livecheck.sh
```

Flow.app reads only the calendar named `FlowTest` by default.

To access all authorized calendars, launch with:

```bash
FLOW_CALENDAR_SCOPE=all
```

Command-line processes such as `swift test` cannot be granted Calendar access in the same way as a properly configured application bundle, so the live Calendar check runs as a small application bundle.

### Accessibility permissions and signing

Window control requires Accessibility permission for the process running it.

This may be Flow.app or the terminal or IDE running `swift test` or `flowctl`.

The build script signs Flow.app with a stable identity so macOS can retain its Accessibility authorization across rebuilds.

```bash
scripts/build_app.sh --open
```

Signing uses:

1. `$FLOW_SIGN_IDENTITY`, if configured.
2. An available Apple Development certificate.
3. A local identity created through `scripts/create_local_signing_identity.sh`.

The script refuses ad hoc signing unless `--allow-adhoc` is explicitly passed because those permissions are tied to the binary hash.

If signing fails with `errSecInternalComponent`, check that Apple's WWDR G3 intermediate certificate is installed and allow the signing process access to the appropriate Keychain key when prompted.

### LM Studio configuration

The default LM Studio endpoint is:

```text
http://localhost:1234/v1
```

The defaults can be overridden with:

```bash
FLOW_LMSTUDIO_URL
FLOW_MODEL_ID
```

Non-localhost URLs are refused.

### Argmax Pro setup

Flow uses Argmax Pro SDK 3.1.8 from Argmax's authenticated Swift package registry.

Configure the registry:

```bash
swift package-registry set --global \
  --scope argmaxinc \
  https://api.argmaxinc.com/v1/sdk
```

Authenticate using your own registry token:

```bash
swift package-registry login \
  https://api.argmaxinc.com/v1/sdk/login \
  --token <SECRET_API_TOKEN>
```

Configure the runtime key:

```bash
cp .env.example .env
```

Set `ARGMAX_API_KEY` in `.env` using your runtime key beginning with `ax_`.

The `.env` file is excluded from version control.

Do not commit registry tokens or runtime API keys.

### Voice pipeline testing

```bash
scripts/flow_voice.sh --once
```

This developer harness exercises microphone input, Argmax transcription, Bonsai interpretation, and a mock consumer. It does not execute computer actions.

### Bonsai benchmarking

```bash
swift run flow-bench \
  --runs 3 \
  --out docs/evidence/T-002
```

### Building without Argmax registry access

```bash
FLOW_DISABLE_ARGMAX=1 swift build
```

This builds the project without the Argmax adapter.

In this mode, `Package.resolved` may be removed locally because no dependencies need pinning.

Do not commit that deletion. Restore the file with:

```bash
git checkout -- Package.resolved
```

## Architecture and Modules

Flow is organized into modules using Swift Package Manager.

### Core intelligence and execution

- **`FlowCore`**: Intent definitions, typed action allowlist, risk tiers, errors, and deterministic control routing.
- **`FlowLLM`**: LM Studio client, Bonsai prompt and JSON schema, strict validation, and classification.
- **`FlowRouting`**: Deterministic routing, stop/cancel commands, task context, references, clarifications, follow-up answers, and Bonsai fallback. The model proposes validated intents and does not directly execute actions.
- **`FlowPlanner`**: Bounded multi-step planning with a maximum of five allowlisted steps, pause/resume, version-bound approvals, and an at-most-once send ledger. The planner is channel-agnostic but implementation of a particular communication channel requires a corresponding adapter.
- **`FlowExecutor`**: Real execution through supported window, accessibility, Mail, Calendar, and sending adapters, subject to their respective restrictions.
- **`FlowSession`**: `VoiceSessionCoordinator`, which connects finalized Argmax utterances to routing, planning, execution, cancellation, and HUD status.

### Voice and interaction

- **`FlowAudio`**: Microphone permissions, utterance endpointing, partial and final transcription handling, voice activity detection, stop/cancel behavior, and routing to the classifier and intent consumer.
- **`FlowArgmax`**: Argmax Pro `LiveTranscriber` integration implementing `SpeechTranscribing`.
- **`FlowHUD`**: Floating display state and placement, including listening, hearing, working, speaking, waiting, transcript history, questions, numbered options, results, and hints.
- **`FlowApp`**: Native SwiftUI application with typed-command tabs for interpretation, window control, UI navigation, Mail, and voice interaction. The Voice tab connects speech and typed commands to the planner and real executor.

### macOS integrations

- **`FlowWindow`**: Application launch and switching, window movement, resizing, tiling, minimizing, restoring, verified state reads, and undo.
- **`FlowAX`**: Generic Accessibility inspection, deterministic target resolution, revalidated clicking, focusing, selection, scrolling, and numbered overlays.
- **`FlowMail`**: Apple Mail search, open, and read integration using scripting and Accessibility, stable message references, and on-screen verification.
- **`FlowMailSend`**: Confirmed Mail sending with draft revalidation, at-most-once dispatch, and classification of Sent, Outbox, not sent, or unknown outcomes. Disabled by default with a separate dry-run mode.
- **`FlowCalendar`**: Read-only EventKit integration, time-expression parsing, availability classification, calendar scope, and optional navigation to a selected day.
- **`FlowText`**: Deterministic text editing through a versioned compare-and-set backend, including append, replace, remove, undo, occurrence resolution, previews, and dictation.

### Developer tools

- **`flowctl`**: Command-line interface for typed window, Accessibility, and Mail operations.
- **`flow-nav-fixture`**: AppKit test application used for Accessibility integration testing.
- **`flow-voice`**: Speech-to-intent developer harness using a mock consumer.
- **`flow-bench`**: Bonsai intent benchmarking.
- **`flow-speech-eval`**: Synthesized-speech recognition and segmentation evaluation.
- **`flow-plan-demo`**: Planner walkthrough using a mock executor.

The developer harnesses do not directly execute computer actions.

## Implementation Status and Evidence

The following workstreams are documented in the repository.

| Workstream | Implementation |
| --- | --- |
| T-002 | Bonsai benchmark harness and results |
| T-003 / T-012 | Argmax speech pipeline and spoken feedback components |
| T-011 | Validated intent classification |
| T-020 | Window control, verification, and undo |
| T-021 | Generic Accessibility navigation and numbered overlays |
| T-022 | Apple Mail read and search integration |
| T-023B | Voice editing of Flow-created Mail reply drafts, with simulated verification and live editing restrictions |
| T-023C | Confirmed Mail sending with explicit approval and dry-run support |
| T-024 | Calendar availability through EventKit |
| T-025 | Versioned text-editing engine |
| T-026 | Bounded task planning and safety checks |
| T-030 | Voice routing, context, clarification, and recognition reliability improvements |
| T-031 | Voice-to-planner-to-executor integration in Flow.app |
| HUD usability | Persistent non-activating HUD, app/window commands, context preservation, and spoken feedback integration |

### Important testing boundaries

- Mail search and reading use a synthetic `FlowTest` mailbox for live executor testing.
- Mail draft editing has simulated coverage, but real application editing is disabled by default until verified.
- Confirmed sending is implemented but remains disabled by default.
- Dry-run sending exercises validation and confirmation without pressing Send.
- Real sending has not been verified through a live external send.
- Calendar access defaults to the `FlowTest` calendar.
- Generic Accessibility navigation depends on the application and the controls it exposes.
- Automated, simulated, and live test results are distinct. A passing simulated test does not guarantee success in a real application.

### Detailed evidence

- [Project evidence](docs/evidence)
- [Architecture decision records](docs/adr)
- [Voice executor integration](docs/evidence/T-031-voice-executor-integration.md)
- [Calendar integration](docs/evidence/T-024-calendar.md)
- [Text editing](docs/evidence/T-025-text-editing.md)
- [Mail draft editing](docs/evidence/T-023B-mail-draft-editing.md)
- [Confirmed Mail sending](docs/evidence/T-023C-confirmed-sending.md)
- [Floating HUD and usability](docs/evidence/HUD-usability.md)
- [Task planning](docs/evidence/T-026-task-planner.md)
- [Voice reliability](docs/evidence/T-030-voice-improvements.md)

## Why Flow?

Flow is built around a simple idea: **accessibility should extend beyond controlling individual interface elements to helping people complete entire tasks.**

Opening a window is useful. Finding the right message, checking a schedule, correcting a reply, and staying in control throughout the process is more meaningful.

Flow explores how local AI, native accessibility tools, and careful execution safeguards can work together to make everyday computer interaction more conversational, continuous, and accessible.

**Your computer. Your voice. Your workflow.**
