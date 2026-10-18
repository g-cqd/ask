---
status: not-started
blocked-by:
date: 2026-10-18
---

# 0006 — Apply the reset ladder on teardown and on signal

`0002`'s own "Still owed" is: *"applying the ladder on teardown and on signal, so the normal path
writes the selective tier and only escalates when the cheap tier demonstrably failed."*

Probed: `AskTUI` writes `TerminalResetLadder.escapeBytes(upTo: .selectiveCleanup)` in a `defer`. There
is **no signal handler and no escalation trigger**. `TerminalKitInput` already ships a public
`SignalHandler` with `start()`; nothing in `ask` calls it.

So the ladder is a correct value nobody fully calls. A `SIGINT` or a crash today leaves the terminal
in the alternate screen with the cursor hidden.

## What is owed

- The selective tier on **every** exit path, not just normal return: signal, and the error path in
  `AskMain` that already runs the ladder before printing.
- An **escalation trigger**: when the cheap tier demonstrably failed, go up. TerminalKit ADR-0002
  measured that DECSTR resets no DEC private mode on kitty, ghostty or wezterm, so tier 2 alone does
  not clear `?1049`, the mouse modes or `?2004` — tier 1 is the one that does.
- A signal handler that restores the terminal and then re-raises with the default disposition, so the
  process still dies the way the user asked it to.

## The trap

A handler that restores and swallows the signal leaves a process that ignores Ctrl-C, which is worse
than the bug being fixed. Restore, then re-raise.

## Done when

Every exit path writes tier 1, a signal both restores and dies, and a test drives each path and
asserts the bytes.

## Not blocked by anything

New behaviour in `ask` itself. Can proceed alongside `0005`.