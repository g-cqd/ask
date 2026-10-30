---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0158 — Unfolding a block at the top of a long session takes seconds

Owner wish (2026-10-30 14:43): "Clicking on a block at the top of a 30k+ lines session, unfolds the blocks after a delay of 2-5
seconds, we should fix that, it blocks the responsiveness."

The action budget is 8 ms; this is 250 to 600 times over it. To do, red first: a measurement (`Scripts/measure-action.py` or a benchmark)
that opens a block near the top of a transcript of 30,000 lines and times the click to the frame; then find what is linear in the
session's length (re-wrapping every block after the opened one, recomputing every row offset, re-parsing Markdown) and make an unfold
cost what the opened block and the visible rows cost. Likely shares its cause with 0160.
