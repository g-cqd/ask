---
status: not-started
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
