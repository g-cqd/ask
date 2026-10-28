---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0083 — Interrupt keys and queued steering are settings

Owner requests, from `ask-wishes.md`. Today Ctrl-C is `interrupt` and Esc is `escape` in `PromptEditor`, and
`ScreenController+Interrupt` needs consecutive presses to abort a turn. Queued steering enters at the next response
boundary, one message at a time (`AgentLoop`, `PromptQueue`).

## Still owed

- A setting for which key interrupts a turn: Esc, Ctrl-C, or both. Name it, give it a default that keeps today's
  behaviour, and validate it in the config editor.
- A setting to send the next queued steering input automatically after a manual interruption.
  - A second setting picks whether it sends only the very next queued input or all of them.
  - Off by default: today an interruption leaves queued input unsent. State what happens to the rest when only
    the next one is sent.
- Tests: each key choice, interruption with an empty queue, with one and with several queued inputs, and an
  interruption during a tool call. Check the queued messages stay persisted in order.

## Conflict with 0064

0064 records the owner direction of 2026-10-24 that Esc never aborts a turn and Ctrl+C is a ladder. The wish of
2026-10-28 asks for Esc, Ctrl-C or both as a setting. Treat the wish as the newer decision: the default stays 0064's
(Ctrl-C), Esc interrupting is opt-in, and 0064 gets a note when this lands. Confirm with the owner before building.
