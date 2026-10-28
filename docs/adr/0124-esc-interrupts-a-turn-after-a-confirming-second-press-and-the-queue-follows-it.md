---
status: accepted
date: 2026-10-28
---

# 0124 — Esc interrupts a turn after a confirming second press, and the queue follows the interruption

## Context

0064 made Esc navigation only and Ctrl+C the one way to stop a turn. The owner decided otherwise on 2026-10-28 (`ask-wishes.md`, 0083).
Codex's source confirms the same split: `chat.interrupt_turn` defaults to plain Esc and can be rebound, and Ctrl+C is a fixed
"interrupt or quit" key.

## Decision

- Esc stops a running turn when nothing nearer wants it (a selection, a picker, the strip, a job lane step back first). By default the
  first press arms ("press Esc again to abort", two-second window) and a second stops the turn. `ui.escapeInterruptRequiresConfirmation`
  turns the confirmation off. Ctrl+C keeps its ladder and its own `ui.abortTurnRequiresConfirmation` (default off, one press).
- `ui.interruptKeys` (`esc`, `ctrl-c`, `both`; default `both`) says which keys may interrupt. Ctrl+C that may not interrupt falls to
  the idle ladder (arm the quit).
- `ui.interruptSendsQueued` (`none`, `next`, `all`; default `all`) says what follows a **person's** interruption: `all` starts a turn with
  the first queued message and the rest join it as steering; `next` starts the first and keeps the rest unsent, each starting its own turn
  as the last ends; `none` returns them to the input (the old behaviour). A failed turn always returns them to the input.

## Consequences

Supersedes 0064's Esc rule. Default behaviour changes: queued messages now follow an interruption instead of landing in the input.
Cancelling stops the turn's tools through the run's cancellation, as before.
