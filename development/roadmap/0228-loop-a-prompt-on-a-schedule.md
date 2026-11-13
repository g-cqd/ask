---
status: done
blocked-by: []
date: 2026-11-13
---

# 0228 — `/loop`: a prompt sent on a schedule, in the main conversation

The owner (note n34, t216; research `development/research/goal-and-loop-2026-11.md`): loops run in the main conversation; a bare
`/loop` with a maintenance prompt and one-shot reminders were not answered, so they are left out.

`/loop 10m TASK` (s, m, h, d; at least a minute) sends TASK as the person's next message every interval, labelled
`[loop N, run R]`; due while a turn runs it is skipped, not stacked, and missed intervals are not caught up. At most 24 runs, for 7
days at most, while ask is open. `/loop` lists them (runs, skips, next); `/loop stop N` and `/loop stop all` end them.
`RecurringPrompts` holds the rules on time offsets (tested without waiting); `RecurringDriver` sleeps until the next is due.

Not done: loops kept across a resume; a model-chosen interval; the maintenance prompt and reminders (unanswered).
