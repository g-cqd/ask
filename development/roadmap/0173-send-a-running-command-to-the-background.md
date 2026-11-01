---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0173 — Send a running command to the background from the keyboard

Wish (2026-11-01): as in Claude Code, a shortcut that sends a running command to the background, then either sends the next queued
message at once or lets the model carry on, told when the job ends.

Background jobs and waits exist (0031): a command's `yield_seconds` hands it back as a job. This is the same move, made by the person.

## Still owed

- The key: Ctrl+Enter, or Command+Enter where the terminal reports it (kitty keyboard protocol, 0003). Check what each terminal ask
  supports sends, and fall back to a key every terminal sends.
- The tool call returns as if it had yielded: job id, output so far; the job then reports its end as 0031's jobs do.
- With a queued message, it is sent right after; without one, the turn goes on.
