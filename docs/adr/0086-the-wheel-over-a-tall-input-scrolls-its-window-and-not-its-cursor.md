---
status: accepted
date: 2026-10-24
---

# 0086 — The wheel over a tall input scrolls its window, and not its cursor

## Context

The input shows at most `ui.promptRows` rows (ADR-0059) and its window follows the cursor. Over it, the wheel scrolled the transcript, so a
long draft could be read only by moving the cursor through it.

## Decision

- **A step of the wheel over the input scrolls its window one display row** when the draft is taller than the window, and leaves the
  cursor and the text alone. The window top is a separate piece of screen state (`promptScroll`) that overrides the usual
  follow-the-cursor rule until something ends it.
- **The input keeps the steps while it can use them.** At either end it stays put and does not pass the rest of a gesture to the
  transcript underneath. A draft that fits has nothing to scroll, so the step goes to the transcript as before. A step over the
  transcript is unchanged. The scroll position cannot be banked beyond an end.
- **A cursor that is not on screen is not drawn.** The terminal cursor is hidden while the window is scrolled away from it, rather than
  parked on an edge where it would point at the wrong text. It comes back when the window does.
- **Anything that acts on the draft puts the window back on the cursor:** a click, a drag or a double click in the input, a Shift
  selection, and every key that edits or moves the cursor, and a paste. A click maps to the rows that are drawn, not to the ones the
  window would show if it followed the cursor, so a click in a scrolled window lands where the user pointed. Keys that do nothing to the
  draft (Ctrl+O, Page Up) leave the window where the wheel put it.
- The clipping cue (`input 6–9 of 10`) describes the window as shown, so it updates with the wheel.

## Consequences

A wheel gesture that starts over the input and carries on into the transcript's rows scrolls the input only until the pointer leaves it;
the recognizer reports each step with the region under the pointer. With `ui.mouse false` nothing is heard.
