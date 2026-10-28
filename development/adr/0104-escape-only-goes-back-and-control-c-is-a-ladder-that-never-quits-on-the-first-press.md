---
status: accepted
date: 2026-10-25
---

# 0104 — Esc only goes back, and Ctrl+C is a ladder that never quits on the first press

## Context

The owner's direction (2026-10-24, roadmap 0064): Esc must not abort a turn; Ctrl+C must not kill ask directly and erases the input; stopping must not be Esc.
Until now Esc cleared a selection and then aborted a running turn, and Ctrl+C copied a selection, then aborted a running turn, then quit when idle (ADR-0056,
ADR-0040, the README). The lane focus of roadmap 0062 needs Esc to mean "go back" everywhere.

## Decision

- **Esc is navigation only.** It clears a selection, closes a picker or list, and otherwise does nothing: it never stops a turn, quits, or clears a draft.
  (A pending approval question still takes Esc as "no", as in ADR-0056, which is an answer, not a stop.) Returning focus from a lane, and from the input to main,
  belongs to roadmap 0062, when there are lanes; today there is nothing to return from.
- **Ctrl+C is one step a press**, in this order: (1) a selection, in the transcript or the input: copy and consume it (ADR-0056, unchanged); (2) a draft: **erase
  all of it**; (3) an empty input with a turn running: **stop** the turn, which cancels the request or stops the tool's process group and returns unsent queued
  messages to the editor, as Esc did; (4) an empty input and idle: **arm the quit** (the status line says `press Ctrl+C again to quit`); a second press within
  **two seconds** quits. A pending question keeps Ctrl+C as "deny and stop" (ADR-0056).
- **Any other key disarms**: the window is read and cleared at the top of every key, so only an immediately following Ctrl+C can complete it. The window is
  checked against the press's time in the controller, and a timer (`armQuitTimer`, a one-shot) removes the hint when it passes; a timer for an earlier window cannot
  close a later one (a generation number).
- **With text typed during a turn it takes two presses** (erase, then stop). No dedicated stop chord that works with text present was chosen: the owner's
  words were "ctrl+c or something else but not esc", and the candidates (Ctrl+\ and an unused Ctrl+letter) stay open.
- **Stopping a tool ends the turn**, as an abort did. Stopping only the tool and letting the model continue is a separate, finer action, not decided.
- **Ctrl+D** on an empty, idle input still quits at once (it is end of input, not an interrupt) and does nothing mid-turn. The owner's direction named Ctrl+C
  only; this is mine and one line to change. `/quit` always quits.
- The status line says `(ctrl+c to stop)` while working, `/help` carries the ladder, the busy-command notice says to press Ctrl+C, and the README says it.

## Consequences

Esc can be pressed freely, by habit, from any other program, without losing a turn. A stray Ctrl+C can lose a draft (which was the request) but never a session.
Cost: stopping a turn while text is typed takes two presses. A script that sent one Ctrl+C to quit now sends two (the probes and the measurement scripts that did
so changed). The supersession is partial: ADR-0056's selection rules and ADR-0040's acknowledgment rules stand, and only their statements that Esc or Ctrl+C
aborts are replaced by this.
