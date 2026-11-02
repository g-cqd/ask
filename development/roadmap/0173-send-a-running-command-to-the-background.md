---
status: done
blocked-by: []
date: 2026-11-01
---

# 0173 — Send a running command to the background from the keyboard

Wish (2026-11-01): as in Claude Code, a shortcut that sends a running command to the background, then either sends the next queued
message at once or lets the model carry on, told when the job ends.

Background jobs and waits exist (0031): a command's `yield_seconds` hands it back as a job. This is the same move, made by the person.

## Done (2026-11-01)

- The key: **Ctrl+B**, which every terminal sends (Claude Code's), and Ctrl+Enter where the terminal reports the modifier (a plain
  terminal sends it as Enter). Only while a command block runs in the turn; otherwise Ctrl+B keeps moving the cursor. Command+Enter is
  not read: no terminal ask probes reports it apart from the kitty keyboard protocol, which ask does not ask for (0003).
- `ForegroundCommands` (on the job table): each shell call's wait races the person's request; a request ends every wait there is, and
  the call returns as a yield does: the output so far, `[sent to the background by the person as job-N …]`, and the job, which then
  reports its end as 0031's jobs do. A cancelled wait still reports itself as aborted.
- Queued messages: nothing new was needed: the loop sends them at its next step, and without one the turn goes on.
- Tests: `ForegroundCommandTests` (a real `sleep 30` sent to the background, still running after), `BackgroundKeyTests`; 5 mutants,
  all killed.
- Not done: a probe through the release binary in a real terminal, and a hint in the status line while a command runs.
