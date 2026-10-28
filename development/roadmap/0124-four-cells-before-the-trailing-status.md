---
status: done
blocked-by: []
date: 2026-10-28
---

# 0124 — Four cells before a block's trailing status, again

Owner, marked as a regression (2026-10-28 22:52): the four-cell space before the trailing status of a block is gone; it should be on
the first line of blocks and in the jobs list.

Cause: 0080 set `ScreenComposer.headerGap` to 2 for every header, and 0100 gave the job rows the same gap. Restore 4 for both.

## Result (2026-10-28)

`headerGap` is 4 again. It is the one constant for the first row of every block (folded one-row headers, open headers, command blocks)
and for job rows below the input, so all of them have four cells before their status. The tests that pinned two cells now pin four.
