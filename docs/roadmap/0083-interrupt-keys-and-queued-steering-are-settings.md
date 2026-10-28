---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0083 — Interrupting a turn: Esc with confirmation, and queued steering, are settings

Owner requests (`ask-wishes.md`) and decisions of 2026-10-28. Today Ctrl-C is `interrupt` and Esc is `escape` in `PromptEditor`,
and `ScreenController+Interrupt` needs consecutive presses to abort a turn. Queued steering enters at the next response boundary,
one message at a time (`AgentLoop`, `PromptQueue`).

## Decisions (owner, 2026-10-28)

1. **Esc interrupts a running turn, by default.** This supersedes 0064's "Esc never aborts" (note added there).
2. **A second press confirms.** A setting says whether the confirmation is needed; the default is *confirm* (press twice). The
   first press shows a hint ("Esc again to interrupt") and expires after a short window.
3. **Which keys interrupt** is a setting: Esc, Ctrl-C or both. Default: both (see the survey for Ctrl-C).
4. **After an interrupt, queued steering** is a setting: send automatically or leave unsent; and when sending, one or all. Default:
   **send all at once**.
5. **Ctrl-C and running tools: follow the most common principle** (survey below).

## Survey: what other harnesses do

Written from memory of their documentation; only pi's row was checked against source (the installed `keybindings.js` has
`app.interrupt` defaulting to `escape`).

| Harness | Esc while a turn runs | Ctrl-C while a turn runs |
| --- | --- | --- |
| pi | interrupts (verified) | clears the editor; twice quits |
| Claude Code | interrupts, one press; Esc Esc on an idle prompt opens rewind | interrupts; twice from idle quits |
| Codex CLI | interrupts the task, one press | interrupts; from idle a second press quits |
| Gemini CLI | cancels the request, one press | cancels; twice quits |
| opencode | interrupts after a second press ("esc again to interrupt") | clears the input; a second press exits |

Reading: Esc interrupts (one press in most, two in opencode); Ctrl-C also interrupts a running turn and quits only from idle on a
second press; an interrupt cancels the in-flight request and the running tools, so none keep running behind the prompt. So Ctrl-C
stops the turn **and** its tools, as the majority does, and the owner's two-press Esc matches opencode. Re-check each row against
current source before this lands.

## Settings to add (names proposed)

- `interrupt.keys`: `esc`, `ctrl-c`, `both` (default `both`).
- `interrupt.confirmEsc`: bool (default `true`).
- `interrupt.sendQueued`: `none`, `next`, `all` (default `all`). When `next`, the rest stay queued, in order, and persisted.

Each validated in the config editor and documented in `ask config`.

## Still owed

- The survey's rows re-checked (opencode and Codex source; Claude Code and Gemini docs).
- Implementation and tests: each key choice; confirm on and off, and the expiry of the first press; interruption with an empty
  queue, one and several queued inputs; an interruption during a tool call (the tool is cancelled, its block shows it); queued
  messages stay in order on disk.
- An ADR when built, superseding the Esc rule of 0064.
