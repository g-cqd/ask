---
status: done
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

Written from memory; checked against source: pi (`app.interrupt` defaults to `escape`) and Codex (`chat.interrupt_turn` defaults to plain Esc;
Ctrl+C is a fixed "interrupt or quit"). gemini-cli has an Esc handler that cancels (`useGeminiStream.ts`). opencode and Claude Code rows are
not re-checked.

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

## Built (2026-10-28, ADR-0124)

Settings, as built (names differ from the proposal): `ui.interruptKeys` (`esc`, `ctrl-c`, `both`; default `both`),
`ui.escapeInterruptRequiresConfirmation` (default `on`) and `ui.interruptSendsQueued` (`none`, `next`, `all`; default `all`). They are in
the config editor, `README.md` and tests (`InterruptSettingsTests`, `InterruptConfigurationTests`). `all` = the first queued message starts
a turn and the rest join it as steering; `next` = only the first starts, the others wait unsent and start their own turns in order.

Not verified: a real terminal session (the controller is tested with synthesised keys); that Esc still reaches ask un-delayed under
tmux and other terminals that hold a lone Esc to tell it from an escape sequence; the interruption of a tool call in flight (unchanged
cancellation path, not re-tested); `next` with a follow-up first in the queue; the survey's opencode and Claude Code rows.
