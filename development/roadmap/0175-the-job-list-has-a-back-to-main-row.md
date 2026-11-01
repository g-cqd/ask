---
status: done
blocked-by: []
date: 2026-11-01
---

# 0175 — The job list has a row that goes back to the main conversation

Wish (2026-11-01): when a job's output is shown (the lane, 0062), the job list should show a clickable "main" row to go back, rather
than the job's details in the status bar with an Esc hint.

## The plan, as first written (the outcome follows)

- A first row `main` in the job list while a lane is open, clickable, drawn as the job rows are; Esc still goes back.
- The status bar shows what it shows in the main conversation, without the lane's Esc hint.

## Done (2026-11-01)

- While a runner's output is shown, the job list (and the sidebar, which draws the same rows) starts with `main  back to the
  conversation`, dim, under the reserved id `RunnerStrip.mainID`; a click on it leaves the lane. The list shows in a lane even when it
  was closed, since it is then the way back. Esc still goes back.
- The status line no longer shows `main › job · esc returns`.
- Tests: `RunnerLaneTests` (the row, its click, a closed list), and the tests that read the old status segment or the strip's first
  row in a lane; each new guard fails a test when removed.
