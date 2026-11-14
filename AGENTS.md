# Flow — Coding Agent Instructions

Before making changes, read:

1. docs/01_Flow_Unified_PRD.md
2. docs/02_Flow_Technical_Behavioral_Spec.md
3. docs/03_Flow_Agent_Implementation_Plan.md

## Required Technologies

- Swift and SwiftUI for the macOS application
- Argmax Pro SDK for speech processing
- Bonsai 2 models (2B, 4B, or 9B)
- LM Studio for local inference
- macOS Accessibility and native automation APIs

Do not substitute cloud LLM APIs or other speech providers without explicit approval.

## Engineering Rules

- Follow the PRD and technical specification.
- Use validated, structured actions for computer control.
- Keep language-model planning separate from execution.
- Never bypass macOS permission requirements.
- Preserve user control over consequential actions.
- Support voice-only recovery within guaranteed workflows.
- Do not hardcode credentials or commit private data.
- Do not invent SDK methods or claim untested integrations work.
- Prefer small, testable changes.
- Report blockers rather than silently changing requirements.

## Before Completing Any Task

1. Run relevant tests and builds when possible.
2. Report which files changed.
3. Report what was tested and the results.
4. Identify unresolved issues.
5. State the next recommended implementation task.
