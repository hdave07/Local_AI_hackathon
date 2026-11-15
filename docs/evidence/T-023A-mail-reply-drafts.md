# T-023A evidence — Apple Mail reply drafting and review (never sent)

**Date:** 2026-11-14 · **Branch:** `feature/mail-reply-drafts`, based on `f4e7291` (main 57717c0 + voice-executor integration, which is not yet merged to main) · **Mail 16.0, macOS 26.6.2**

## How it works
- **Creation:** one Mail scripting call per reply (`replyDraft`).
  - Revalidate the original (same Message-ID, subject, sender).
  - Refuse if a reply to it is already open (no duplicates).
  - Create the reply **hidden** with `replyToAll: false`; require `To == [original sender]` and empty Cc/Bcc. Otherwise discard the never-shown reply and report `recipient_mismatch`.
  - Set the text, then show the window.
- **Verification is independent of scripting** (`AXMailComposeInspector`). It needs exactly one visible compose window with that subject, one To token matching the sender, empty Cc, and the requested text visible in the "message body" web area. A window existing isn't enough; otherwise the result is `unverified`.
- **Drafts and versions:** Mail gives unsent messages no identity (id 0), so `MailDraftController` keeps Flow's own draft registry, mapped to FlowPlanner's `DraftSnapshot`. Threading uses `inReplyTo` = the chosen `MessageRef`.
  - Every review re-reads the live draft: recipients via scripting, body via Accessibility.
  - Any difference from the last verified state means **version + 1** and the snapshot is replaced.
- **No duplicates:** each plan step creates at most one draft (`planID#stepID`). An already-open reply to the same message is reused only if its text matches; otherwise it's refused. A timeout returns `unverified` and is never retried automatically.
- **Disabled:** `request_send` → `unsupported` ("Nothing was sent"). Editing by voice (`insert/replace_text`) is still unsupported. No send, save or delete operation exists in Flow.
- **Routing (FlowRouting/FlowPlanner):**
  - "Reply saying …" / "reply to it saying …" / "reply to Sarah's / her / that email saying|that …" reply to the **verified open message**; the recipient is its sender, never guessed from recent people.
  - "reply to it" → "What should the reply to Sarah Chen say?", and the next utterance is the content: kept whole, still threaded, with "say …" removed.
  - "Reply to Sarah's email saying …" with no matching email open → find it, ask which (two Sarahs), then reply.
  - A trailing "and show it to me" becomes a review step.
  - "I want to …" and openers like "Actually, never mind." are stripped.
  - "never mind" / "forget it" cancel, including an open question.
  - "delete / discard / close that reply" → "I can't delete or discard drafts. The reply is still open in Mail and hasn't been sent; you can close it there."
  - "the reply we just drafted" / "what does the draft say" → show the draft.

## Live results (real Mail, synthetic FlowTest only)
| Test | Result |
|---|---|
| Find Sarah's email → choose → "Reply saying FLOWTEST SAFE: I can meet at 3" | `create_draft → completed`; To `sarah.chen@example.invalid` only, subject "Re: [FlowTest] …", text on screen (independent AX read), exactly one new unsent draft, Sent unchanged |
| "…and show it to me", then a recipient added outside Flow, then "show me the draft" | review v1, then **v2** "changed outside Flow"; snapshot replaced; reviewed version 2 |
| "reply to it" → question → dictated answer; a second different reply | draft created only after the answer; second **refused** (`draft_already_open`), still one draft |
| "Reply saying …" while still choosing a Sarah; then send + yes | no draft without a chosen message; `request_send → unsupported`, nothing sent |
| User's voice run (before fixes) | Correct recipient/thread/unsent draft, but body "email that I can meet at 3:30"; delete request and draft reference fell through to the model ("Which email should I look for?") |

Test drafts are removed by a **test-only** helper. It closes only drafts with subject "Re: [FlowTest]…", every recipient @example.invalid, and body starting "FLOWTEST SAFE:", and moves autosaved copies of those to Trash. After the runs: 0 test drafts open or saved. The user's own draft "Re: [FlowTest] Meeting tomorrow" (open + autosaved) was left untouched.

## Automated results
`FLOW_LIVE_AX=1 FLOW_LIVE_MAIL=1 swift test`: **455 passed.**
- New: 20 FlowMail drafting tests; 11 reply-draft TaskSession + executor integration tests (including the user's session replayed); 4 live draft tests; 33 routing and 5 planning reply regression tests.

## Limitations
- **Threading** is guaranteed by creating the draft with Mail's `reply` on the revalidated message, and checked as "Re: subject" plus the sender. The In-Reply-To header of an unsent draft isn't readable through Mail scripting.
- **Mail autosaves open drafts** into the account's Drafts (it may sync to the server). That's normal Mail behaviour; Flow never saves or deletes.
- **Recipient-mismatch (Reply-To / Cc)** is verified with simulated Mail only. The FlowTest fixtures have no Reply-To or multi-recipient messages.
- **Draft identity is by subject plus registry.** Two open replies to the same message are refused as ambiguous rather than guessed.
- **Not supported yet:** editing a draft by voice ("change 3 to 4") and sending (disabled).
- Phrasings outside the deterministic patterns still fall back to the language model (slow, 6–10 s).
