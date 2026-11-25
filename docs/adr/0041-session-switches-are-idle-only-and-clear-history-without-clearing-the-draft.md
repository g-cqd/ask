---
status: accepted
date: 2026-10-20
---

# 0041 — Session switches are idle-only and clear history without clearing the draft

## Context

Starting another conversation should not require leaving the screen. Sessions have exclusive writer locks,
usage belongs to their recorded exchanges, and the agent loop can learn a smaller context window from a reply.
None of those should silently carry across a switch.

Jobs, by contrast, belong to the process. Moving a running server into an unrelated conversation without saying
so would hide its owner from the user.

## Decision

- Session-switch commands run only between agent runs, through the same command/busy boundary as reload.
  Steering and follow-ups keep that boundary busy until consumed or returned to the editor.
- A switch refuses while any background job is running, naming the jobs and asking the user to stop them.
  It does not stop a job as a side effect. Completed jobs and retained output remain process-scoped.
- `/new` releases the active recorder and its writer lock, clears cumulative usage and learned-window loop state,
  and leaves the replacement session absent. The next prompt creates its file; a command alone creates none.
  The previous file is not modified.
- A `clearConversation` update clears the transcript, usage display and scrollback, not the editor or model.
  A draft typed while the command runs belongs to the user and must survive.
- Transcript revisions stay monotonic across a clear. The renderer may coalesce clear and replay into one frame;
  a fresh `Transcript()` would reuse revisions and could keep stale cached lines.

## Probes and cost

The coalesced-frame regression fails with a fresh transcript and passes with monotonic revisions.
PTY N checks new-before-first-prompt, two separate archives, old-file preservation, writer-lock release,
provider context and usage. PTY O checks bad arguments, jobs and retained context after refusal.
Seven compiling mutations are caught by the controller tests or actual-binary probes.

Diary 34 records measured startup/input costs and the invalid comparisons discarded along the way.

## Consequences

This commit delivers `/new`. Resuming a selected existing session and switching the model remain in roadmap
0050. A future resume must open the replacement before dropping the current writer, so failure leaves the
current conversation intact; the activation seam accepts an already-open recorder for that purpose.

Pending input remains a non-durable draft (ADR-0040). Explicitly starting a new conversation does not erase it,
but submitting it afterward intentionally places it in the newly selected conversation.
