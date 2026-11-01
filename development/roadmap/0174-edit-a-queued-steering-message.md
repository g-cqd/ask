---
status: done
blocked-by: []
date: 2026-11-01
---

# 0174 — Edit a queued steering message before it is sent

Wish (2026-11-01): Option+Up takes the last message queued for steering back into the input, unsent, to edit it; Enter queues it
again.

## Still owed

- Option+Up with queued messages takes the newest one out of the queue into the input (with what is typed there kept, or refused
  while the input holds text: decide). With none queued, Option+Up keeps its current meaning.
- A message the loop has already taken cannot come back; the key then does nothing and says so in the status line.
- Tests: the message never reaches the model while it is being edited, and its order among the others is kept when it is queued
  again (or it goes last: decide).

## Done (2026-11-01)

- Option+Up with an empty input asks the agent to let the newest queued message go (`withdrawPrompt`); once it answers
  (`promptWithdrawn`), the message is in the input and its queued block reads "Taken back to edit.". With text in the input, the
  status line asks to clear it first; with nothing queued, the key goes on to the editor. One withdrawal at a time. While a stop
  returns the input, the queue is the screen's own and the message comes back at once.
- `PromptQueue.withdraw(id:)` refuses the message the loop is recording; the loop now removes the message it recorded by its id, since
  a withdrawal can move the others. A message already taken stays sent, and the status line says so.
- Queued again, the message goes last, with a new id (decided here: it was edited, so it is a new message).
- Tests: `PromptQueueTests` (withdrawal during a write, removal by id), `SteeringControllerTests` (3); each guard fails a test when
  removed.
