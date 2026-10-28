---
status: accepted
date: 2026-10-25
---

# 0110 — A focused runner takes the transcript, and the main conversation waits inside it

## Context

Roadmap 0062 step 2: the strip (ADR-0105) must be reachable by keys, a runner must be focusable, and Esc must go back. Today the only runners are background jobs,
which have no conversation: focusing one can only show its output. Subagents (0063) will have transcripts and use the same mechanism.

## Decision

- **Reaching the strip.** With the strip open and no picker, **Down** at the end of the draft (an empty draft is the end) selects the first row. The roadmap
  said "from the last line"; the cursor at the very end is the condition, because Down in the middle of a wrapped last line still moves within the draft.
  Up and Down move and stop at the ends; **Right** opens a collapsed parent and **Left** collapses an open one, or goes to the parent from a leaf or a collapsed row;
  **Enter** focuses; any other key gives the keys back to the input and is typed there (so a stray key never vanishes). A collapsed parent's row says
  `N hidden`. The selected row is bold; everything else stays dim (no marks or fills). A **click on a row is Enter**; every click has a key (ADR-0044).
- **Focus is a swap.** `state.lane` holds the main conversation (its transcript and scroll position) while `state.transcript` is the runner's output. Everything that
  already works on `state.transcript` (drawing, selection, copy, folds, scrolling) therefore works on the lane without a second code path. Updates from a run
  are applied to main (`onMain`), so an answer that arrives while a job is shown is there when the user returns. A lane's transcript has its own revision base, because
  per-transcript revision numbers collide and the layout cache would draw the other conversation's lines.
- **Esc goes back one step**, after a selection and a picker have had it (ADR-0104): the strip's selection returns to the input; then a lane returns to main, exactly as
  it was; then an open strip closes. It never touches the draft or a turn.
- **A job's lane shows a snapshot of its output**, read when it is focused (`JobTable.outputTail`, the last 64 KiB of the job's output file, from a whole line,
  with the cut said), through `Conversation.runnerOutput`. It does not follow the job: nothing polls. Focusing it again re-reads.
- **There is one input slot and it sends to main.** A job has no conversation to send to, so typing while a job is shown sends to main, and sending **returns to
  main** so the reply is seen. The status line reads `main › job-1 · esc returns`. Nothing a person types is ever sent to a runner. (For subagents, 0063 changes
  where the one slot sends, and the route text already names it.)
- **A focused runner that ends** returns to main with a notice, never to a blank lane. Output that arrives for a lane that is no longer shown is dropped.

## Not built

Approvals following the lane (step 3), the sidebar (step 4), `/agents`, and a live (following) job view. Left and Right are inert outside the strip.

## Consequences

The mechanism is verified against real processes before subagents exist. A swap is cheap (two struct moves) but anything that must act on main while a lane is shown
must go through `onMain`; today that is every conversation update. The lane's layout is rebuilt on entry and exit, because the composer's cache holds one transcript.
