---
status: accepted
date: 2026-10-25
---

# 0105 — The runner tree is built on update, and its strip sits below the input

## Context

Roadmap 0062 starts with jobs, before subagents, so the layout can be checked against real processes. ADR-0066 supplied a count and an optional flat list above the
status line. The owner wants the runner tree below the input, and eventually in a sidebar, with one input slot. This is step 1 only: the model and the strip.

## Decision

- `RunnerInfo` adds a stable id (defaults to the job's name), parent id, kind and state. Existing job summaries provide root nodes, kind `job`, state `running`;
  finished jobs are already removed from that stream. The model also represents waiting, done, failed and stopped without pretending those lifecycle events
  are supplied today. An `agent` kind is a value, not an implementation of subagents: none are started or advertised.
- `RunnerTree` is built when a snapshot changes (`ScreenState.runners` setter). Its unique nodes, cached preorder rows and active counts are one source for
  the strip and status, and later the sidebar. Rendering does not rebuild the tree. Only running and waiting-for-approval count as active. An all-job count
  says `jobs`; a mixed count says `runners`.
- First occurrence of an id wins; parents precede children even when the update supplied the child first; siblings keep update order. Missing and self parents
  become roots. Cyclic components are rooted at their first unseen node in update order, and every id is visited once: malformed topology must not lose a job
  or loop. Traversal uses an explicit stack, O(n) expected time and O(n) space, n = supplied runners, without call-stack depth proportional to n.
- `/tasks` and a click on the status count still toggle the strip. It is **below the one input**, after status and picker, taking at most five rows from the
  transcript while leaving it one. Overflow reserves the last strip row for `… N more`. Rows show indentation, name, detail and state, text only. Indentation
  is limited to screen width, so a deep tree cannot allocate a huge per-frame string. With the strip closed or no runners, it takes no rows.
- Moving the input moves its hit-testing and terminal cursor too. The picker's match geometry now follows the status directly, not the former panel. The strip
  is not transcript content and cannot be selected as if it were. Esc, after selection and picker have had it, closes the strip without clearing the draft or
  stopping a turn (ADR-0104).

## Consequences and limits

This supersedes only ADR-0066's placement and flat presentation. Jobs still supply the live data, and the count, click and `/tasks` routes remain. The first real-PTY
probe checks a real server job's strip below the input, clicks into the moved input, leaves the draft intact on Esc, and stops the server.

Not built here: selecting a strip row, collapse/expand, focusing job output, lane routing, approvals from child lanes, or the sidebar. There is still only the main
conversation and input; clicking a job row does not focus output yet. Roadmap 0062 remains in progress. These are separate behavior changes rather than inert
controls that appear to work before they have a destination.

## Cost

The same release benchmark harness measured the old list and new strip with 0, 5 and 50 jobs, three interleaved A/B pairs. No-runner medians were identical in each
pair (18, 18, 19 µs). With five or fifty nodes, the strip costs about 2 µs more per keystroke frame (roughly 20–21 → 22–23 µs), including the new state text; it does
not scan all fifty nodes to draw five. Load was 8.8–9.4, not idle, and tails were noisy (diary 2026-10-25 (18)). This is a measured cost, not a performance improvement.
