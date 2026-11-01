---
status: not-started
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
