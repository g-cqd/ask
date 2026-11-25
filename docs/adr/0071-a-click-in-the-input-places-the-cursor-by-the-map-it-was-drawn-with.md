---
status: accepted
date: 2026-10-23
---

# 0071 — A click in the input places the cursor by the map it was drawn with

## Context

The input was keyboard-only while everything above it answered the mouse. TerminalKit's `InputLayout` maps source offsets to display
cells in both directions (its ADR-0032), and ask draws the input from exactly that map (ADR-0059), so the reverse lookup a click needs
already exists.

## Decision

- The frame the renderer publishes (`FrameGeometry`) now carries the input's first screen row, how many rows it drew, the draft's display
  row at the top of the window, and the `InputLayout` itself (a reference to the arrays the composer already holds, not a copy of them).
- The input is a pointer region of its own. A click, at any click count, maps its cell to `top + row - firstRow` and the column, and
  `InputLayout.offset(atRow:column:)` gives the character: the one under the cell, the nearest caret on that row when the click is on the
  prefix or past the end, and *before* a wide character for either of its cells.
- The cursor is moved by `PromptEditor.place(cursor:)`, which also forgets the column a previous Up or Down was aiming for, so the next
  vertical move starts from where the user clicked. The transcript selection is dropped, as typing would drop it.
- While a question waits for an answer (a sandbox approval), the keys and the pointer both belong to it: a click places nothing. With
  `ui.mouse false` nothing is heard at all.
- Like every other click, it means the frame that was drawn. If the text changed since, the offset is clamped to the draft, never trusted.

## Consequences

A drag that starts in the input still selects nothing, and the wheel over the input still scrolls the transcript. **Selecting text inside the
input, a wheel that scrolls the input's own window, double-click to take a word, and edge autoscroll while dragging in the input are not
done**; they need a selection model for an editable draft, which is separate from the content selection the transcript uses.
