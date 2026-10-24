---
status: accepted
date: 2026-10-24
---

# 0072 — The view holds while text arrives below, and the status line counts it

## Context

Roadmap 0051 proposes an "N lines below" indicator that scrolls to the end. Before building it, a unit probe showed what happens to a
reader who has scrolled back while a reply streams: `scrollback` counts lines **from the bottom**, so new lines at the bottom moved
everything the reader was looking at down by as many lines (lines 28 to 36 on screen became 31 to 39, with `scrollback` still 3). An
indicator with a constant number over a screen that slides would be wrong, so the two are decided together.

## Decision

1. **A reader who has scrolled back stays on what they were reading.** When an update adds rows to the tail of the transcript while
   `scrollback > 0`, the controller adds the same number to `scrollback`. A reader at the end (`scrollback == 0`) keeps following the
   end, as before.
2. **The rows are counted where they are wrapped.** Before and after the update the controller wraps the block that was last, and any
   block that came after it, at the width of the last frame, through the composer's own `lines(in:at:columns:)`. This is the cost,
   and only a scrolled-back reader pays it: no allocation or wrapping happens at the end, and nothing happens before a first frame.
   A change in the middle of the transcript is not measured; streaming and tool results touch the tail, and a folded tool's finish does
   not change its row count.
3. **An update that sets the position itself is left alone.** A question that sends the reader to the end, and a cleared conversation,
   set `scrollback` to zero; the hold never adds to a position the update has chosen. The position never goes below zero.
4. **The status line says how many lines are below**: `12 lines below`, `1 line below`, nothing at the end. It follows the activity and
   precedes the job count, so a narrow screen keeps it before the details. It is shown with `ui.mouse` off as well.
5. **Three ways to the end.** A click on the count; **End when the draft is empty** (with words in the draft End is still the editor's
   and goes to the end of the line); PageDown, as before, a page at a time. A click elsewhere on the status line does what it did.

## Consequences

At the end of the conversation the hold costs nothing measurable (under a microsecond a delta). A scrolled-back reader pays for wrapping
the tail twice per update: measured through the real composer, a median of 19 µs a delta over 5,000 blocks with a short last block and
123 µs when the last block is 200 lines (p95 207 µs). It runs where updates are handled, not on the keystroke path, and a provider
sends tens of deltas a second, so the worst case measured is about one hundredth of a second of work per second. A last block of
thousands of lines would cost proportionally more; that is the number to watch, and a wrap of only the appended text is the fix if it
ever matters.

## Not decided here

Whether a resize should hold the view too (a rewrap changes every count; `scrollback` is not rewrapped today), a count of lines
below for the runner list, and a status-bar approval chip.

## Probes

Unit tests with the pointer rig (the composer that draws and the controller that decides), including the case that crashed the
test process while it was being written (a transcript that shrinks below the block the hold started from); mutants on every line of
the hold and the line; a real-binary PTY probe with a control. Results are in diary 2026-10-24 (21).
