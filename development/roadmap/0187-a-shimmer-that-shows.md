---
status: in-progress
blocked-by: []
date: 2026-11-01
---

# 0187 — A shimmer that shows: the header dimmed under it, and a smoother pass

Owner wish (2026-11-01 15:41): the shimmer (0171) is not visible enough and looks laggy; maybe it should update faster; the text under it
should be slightly more transparent while it shimmers. The shimmer goes against an accessible contrast ratio anyway, so it may go a
little out of its way.

Today (`ScreenComposer+Shimmer.swift`) a four-column stretch of a running block's header is drawn bold, or undimmed when the header is
dim, moving two columns per spinner tick; the rest of the header is unchanged.

## Still owed

- The header dimmed while it shimmers, so the bright stretch stands out against it; restored when the block finishes.
- A smoother pass: one column a step, at a rate of its own (not the spinner's), and a softer edge (a column of half brightness on each
  side), measured against the input and action budgets (4 ms, 8 ms) and idle CPU.
- Screenshots on light and dark pages for the owner before it ships.

## Done (2026-11-01), waiting on the owner's look

- The header is fainter than dim while it shimmers: still dim, its colour three quarters of the way from the page to the text
  (`ScreenTheme.shimmerBase`). The stretch is a bold core of 4 columns in the text's own colour, with one column of the page's
  secondary colour on each side for a softer edge.
- It glides: its place comes from the block's elapsed time, 20 columns a second, and the progress timer ticks every 60 ms while a running
  header shimmers (200 ms otherwise, and always with `ui.shimmer` off). Spinners keep their 200 ms pace: a tick between frames only
  redraws the live blocks, and the timer keeps the remainder, so frames average 200 ms at any tick.
- Measured on the release binary, a `sleep 6` running: 67 frames in 4 s with the shimmer, 22 without; 0.5% of a core either way (`ps`).
- 8 tests; each of 4 guards, mutated, turns them red. A preview rendered from these colours (dim drawn as half the colour, as Ghostty
  does), dark and light pages, before and after: `/tmp/ask-claude-rcIb/shimmer/shimmer.svg.png` on the machine it was made on.

Still owed: the owner's look in a real terminal.
