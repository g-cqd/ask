---
status: accepted
date: 2026-10-23
---

# 0066 — Background jobs are counted in the status line and listed by a click or /tasks

## Context

Roadmap 0051 lists, among the owner's examples, a count of **runners** (background jobs and subagents) in the status bar that opens a
list of them with short descriptions. ask has background jobs (ADR-0027) but no subagents, and the screen could not see either:
`JobTable` was known only to the tools and to `/reload`.

## Decision

- **One seam, `RunnerInfo` (name and detail), for anything that runs beside the conversation.** Today only background jobs supply it;
  a subagent will supply the same type. The composition root sends the whole list as `ConversationUpdate.runners`, replacing the
  last one, so the screen holds no job state of its own.
- **The table announces its changes; nothing polls.** `JobTable.changes()` yields the running jobs now and again whenever one starts or
  ends (a job's ending is awaited the way `job_stop` awaits it). A slow reader gets the newest list, not every list. The composition
  root's `background` task, which already watched for a new binary, forwards them.
- **The count is a text segment of the status line**, `· 2 jobs`, not an icon or a button. A click on exactly those cells opens the
  list; a click anywhere else on the status line does nothing. The count is **not** counted in the click for any other purpose. The
  click counts as a toggle at any click count: two quick clicks are the user closing what the first opened, not a double click.
- **The list is rows, not an overlay.** Open, it takes up to five rows between the transcript and the status line, one `job-3  command`
  per runner (line breaks shown as spaces), then `… N more` when they do not fit. The transcript gives those rows back when it closes.
  It leaves one transcript row on the smallest screens and is not content: nothing in it is selected or copied.
- **Keyboard and mouse-off access is `/tasks`**, a screen command like `/help`: it toggles the list, or says nothing is running. With
  nothing running the list closes by itself and stays closed when jobs come back.
- **Read-only.** The list shows what runs; it does not stop anything. Stopping a job by click is a destructive action with no
  confirmation step in this model, so it is a separate decision, not part of this one.

## Consequences

The status line's runner segment shifts later segments right, and the count is clipped with them on a narrow terminal; a clipped
count still opens the list, because the cells the click maps to are computed from the text actually written. Subagents, durations,
per-runner output and a way to stop or focus a runner are open (roadmaps 0027 and 0048). The string `job-N` is the model's own name for
the job, so what the user sees is what `wait` and `job_stop` take.
