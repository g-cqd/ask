---
status: done
blocked-by: []
date: 2026-10-28
---

# 0112 — Pressing Right twice sends "continue"

Owner wish (2026-10-28 19:22): pressing the Right arrow twice sends a continue message to the model.

Related to 0097 (a `/continue` command and bare words): this is the key for the same message, so both should send the same text.

## Still owed

- When it applies: only with an empty input (otherwise Right moves the cursor), and only when no turn is running, or queued like any prompt.
- The time window for "twice", shared with the existing double-press handling if there is one.
- The exact text sent, and how it is shown in the transcript.
- Tests for the window, a non-empty input and a running turn.

## Result (2026-10-28)

Right pressed twice, within 600 ms, on an empty input while no turn runs, sends the same message as 0097. It does nothing while a turn
runs (a stray double tap must not steer), with text in the input (Right moves the cursor), when another key came between, or on an
auto-repeat (a held key is not a second tap). Decided without asking, as the wish left it open: say if it should also work during a turn.
