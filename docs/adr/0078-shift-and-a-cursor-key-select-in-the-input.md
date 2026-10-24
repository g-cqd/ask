---
status: accepted
date: 2026-10-24
---

# 0078 — Shift and a cursor key select in the input

## Context

The input could be selected by a drag (ADR-0076) and by double and triple click (ADR-0077), but not from the keyboard, and the screen
promises that nothing needs the mouse.

## Decision

- **Shift with Left, Right, Up, Down, Home or End** moves the cursor exactly as the unshifted key would (so Up and Down follow the
  display rows the input is drawn with, ADR-0059, and Home and End stay hard-line operations) and keeps a selection from where the
  cursor was when the first of them was pressed to where it is now. Going back to that place leaves nothing selected, and crossing it
  flips the selection to the other side.
- **Ctrl, Alt, Super and Meta with Shift are not selections.** Those chords mean other things in terminals and editors, and no feature
  here relies on the modifiers other than Shift and Ctrl-letter.
- The result is an ordinary input selection: highlighted, replaced by typing, deleted by Backspace, copied by Ctrl+C (and consumed),
  cleared by Escape, dropped by any other key. It is **not** copied when it is made: there is no moment like a button release at which
  to copy, and copying on every keystroke would overwrite the clipboard. The status line names Ctrl+C.
- It takes over from a selection in the transcript, as the mouse selections do.
- A waiting approval question keeps the keys.

- It needs TerminalKit `c0be417` (ask pins it): before it, a legacy CSI key's modifier was misread (Shift arrived as Shift+Alt+Super), so these
  keys never reached the selection code in a real terminal.

## Consequences

A plain arrow key with a selection drops it and then moves, instead of collapsing to the selection's edge as some editors do. Cut
(Ctrl-X still clears the whole draft, ADR-0059) and word-wise selection (Ctrl or Alt with Shift) remain undone.
