---
status: accepted
date: 2026-10-20
---

# 0040 — Queued input is acknowledged only after it is persisted

## Context

The screen used to reject a second prompt while a run was active. The loop already knew where a response and
its tool results were complete; that is the safe boundary for steering, not mid-stream or between tool results.
A follow-up has a different boundary: when the model has finished its pending work.

Delivery to a task is not acceptance. A message can reach a queue just after the loop's last boundary but before
the screen learns that the run ended. Treating delivery as acceptance loses it in that race.

## Probes

Release tests cover tool batches, pauses, FIFO and priority, failure, cancellation, the turn limit and persistence
failure. Controller tests place input in the completion race and acknowledge messages during abort.
Real-PTY probes J–L check actual provider requests, the archive and the returned draft.
A live Haiku run produced `STEERED_OK`, then `FOLLOWUP_OK`, with three user entries, each recorded once.
The measured costs and counterfactuals are in diary 31.

## Decision

1. Enter while a prompt runs queues steering. `/follow-up TEXT` queues a follow-up; Alt+Enter is its shortcut
   on terminals that report modified Enter. A queued message is shown as pending, not as already accepted.
2. The loop accepts at most one message after each complete response and all its tool results. Steering is FIFO
   and has priority over follow-ups. Follow-ups become eligible only when the run would otherwise finish.
   Automatic output-limit, context-window and paused-turn continuations are still pending work.
3. A `PromptQueue` belongs to one run. Producers append; the loop alone consumes. It records the user entry,
   removes the queued copy, then emits `promptAccepted`. Persistence failure leaves it queued. Cancellation
   is checked before acceptance; the last allowed turn cannot consume input it has no turn left to answer.
4. The screen retains its own identified copy until that acknowledgment. On normal completion it starts any
   unacknowledged message in a new run and reoffers the rest. This closes the final-boundary race.
5. Abort or failure restores only unacknowledged messages alongside the unfinished draft, in arrival order,
   separated by blank lines. Input submitted during abort stays local. Already recorded messages stay recorded.
6. Queue locks do not span file I/O: snapshot the next message, persist, then remove it. Since producers only
   append and there is one consumer, its index stays valid. A barrier flush or a repaired-file rewrite must not
   lock input producers out.

## Consequences

The loop remains usable without interactive input: its new argument defaults to nil. The TUI remains independent
of the agent through `Conversation.enqueue` and explicit acknowledgment updates.
Messages are ordinary persisted user entries, so replay, compaction and reload need no new session format.

Pending input is in memory, not a crash-durable draft. Explicit quit discards it. A command in progress is not
an agent turn: submitted prompts stay in the editor, and other busy commands still refuse.
The editor now renders hard newlines in returned input; creating and navigating multi-line prompts is the next
unit (0049), not claimed complete here.
