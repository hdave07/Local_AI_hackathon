# ADR 0006 — Apple Mail read/search (FlowMail) and proposed shared contracts

**Status:** Proposed (FlowCore items need Track B agreement) · **Date:** 2026-11-14 · **Owner:** Track A (`feature/mail-integration`)

## Context
T-022 (spec 02 §9, PRD D-016, gate G-04) adds read-only Apple Mail search, open and read. FlowCore is co-owned, so this branch makes **no FlowCore changes**. FlowMail reuses FlowAX (`NavigationStatus`, `AXUIBackend`, `LabelText`) and FlowWindow.

## Decisions
1. **Mail scripting through JavaScript for Automation via `/usr/bin/osascript`, out of process.**
   - Every request is one JSON argument (argv), never spliced into script text, so there's no script injection; a unit test passes a shell-injection string through intact.
   - Results come back as JSON. Only the numeric OSA error code is kept, because stderr can contain message text.
   - Running out of process keeps slow Mail queries off Flow's main thread. macOS attributes the Automation consent to the responsible app (Flow.app, or the terminal for tests).
2. **Open with Mail's `open` command (message in its own viewer window),** not by setting the viewer's selection. On Mail 16.0 / macOS 26.6 JXA can't assign `selectedMessages`/`selectedMailboxes` ("Can't convert types", -1700). AppleScript can switch the mailbox but didn't select the message, and `selected mailboxes` returned values AppleScript couldn't iterate.
3. **Stable reference** `MailMessageRef(messageID: RFC 5322 Message-ID, mailbox: account + path, internalID: Mail id)`. Every open or read first re-reads the message at (mailbox, id) and refuses if it's gone, the Message-ID differs, or the subject or sender changed.
4. **Verification uses three independent signals:**
   - Mail's front window name (scripting);
   - window title on screen (AX);
   - first line of the body rendered on screen (AX).
   All three → `completed`; some → `unverified`; none → `failed`.
5. **Read-only.**
   - `MailBackend` exposes only `availability`, `search`, `lookup`, `lookupWithContent`, `open`, `content`.
   - The script exposes only `status`, `search`, `lookup`, `content`, `open`.
   - Flow never writes flags. If Mail marks a message read on open (its normal behaviour), Flow reports it as an observation (user decision, 2026-11-14).
6. **Privacy.**
   - Bodies are returned only in `MailResult.content` and shown in the UI. `report` strings never include them.
   - FlowMail has no logging or file writes.
   - All processing is local; nothing is sent to the model.

## Proposed shared-contract changes (for Track B review)
1. **`FlowAction.readMessage(query:)` → structured query.** Today it carries one string. Proposal: `findMessage(sender: String?, subject: String?, terms: [String], mailbox: String?)` plus `openMessage`/`readMessage` with the same fields (or a `MailQuery`-shaped struct in FlowCore). The validator keeps lengths bounded. This lets "find Sarah's email about tomorrow" map without re-parsing free text in Track A.
2. **Numbered choice is shared across modules.** ADR 0003 §2 proposed deterministic routing of "choose N". Mail uses the same pattern, so the router needs a context-free `selectNumber(Int)` that the executor dispatches to whichever module offered the most recent numbered set (navigation overlay or Mail candidates).
3. **"Read it" / "read this message"** should be a deterministic (or model-validated) `readActiveMessage` action resolved by the executor from `MailController.activeMessage` (spec 02 §2 `TaskContext.selectedMessage`). Proposal: add `TaskContext` (plan 03 §3) to FlowCore with `selectedMessage: MailMessageRef?` once refs move to FlowCore.
4. **Move `MailMessageRef` and `MailMessageSummary` to FlowCore** when the planner (T-026) needs them. They're Sendable, Codable and contain no body text.
5. **Status vocabulary:** reuse ADR 0001/0003's shared status proposal (`completed / partially_completed / failed / unsupported / unverified / needs_clarification`). FlowMail already uses FlowAX's `NavigationStatus`.

## Consequences
- The future executor calls `MailController.perform(.openMessage(ref))` or `.readMessage(ref)` for planner-held refs, and these always revalidate.
- Classifier output is still not connected to execution.

## Relation to ADR 0005 (planner/executor contract, merged from main)
- **ADR 0005 Q2 (Mail message identity and epochs):** FlowMail identifies a message by RFC 5322 Message-ID + mailbox (account + path) + Mail's scripting id (`MailMessageRef`). There are no result-set epochs: every open or read re-reads the message at (mailbox, id) and refuses if the Message-ID, subject or sender differ. A candidate list is single-use and expires after 5 minutes. `MailMessageRef` is a natural fit for ADR 0005 §1's proposed `MessageRef`.
- **ADR 0005 Q3 (search input):** structured filters, as in §1 above. `MailQuery(sender, subject, terms, mailbox)` is what FlowMail executes; Track A doesn't re-parse verbatim speech.
- **ADR 0005 §1 / §4 (shared status and choice shape):** FlowMail already returns the shared status vocabulary (via FlowAX `NavigationStatus`) and a numbered `MailClarification`. It's compatible with a unified `needs_clarification` + options observation.
- FlowMail doesn't yet implement `PlanExecuting`. Wiring it to the planner is a follow-up once the FlowCore types in ADR 0005 §1 are agreed.
