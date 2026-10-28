---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0107 — A debug mode that shows what ask is doing, in yellow system blocks

Owner wish (2026-10-28 17:34), not a priority: a debug mode that writes a different kind of session file and shows system blocks, tinted
yellow, so a developer sees what happens inside ask. What to show is still to be defined.

## To define with the owner

- How it is turned on (`--debug`, `ASK_DEBUG`, a `/debug` toggle) and whether it is ever on in a release build.
- What the session file holds that a normal one does not, and whether it is kept apart (a `debug` folder) so a normal resume never reads it.
- Candidates for the blocks: each request's budget (window, reply limit, compaction threshold), retries and their wait, the thinking control
  sent, cache reads, hook decisions, sandbox profile changes, timings against the 4 ms and 8 ms budgets.

## Plan

Investigation only until the list is agreed; then a `.system` transcript kind (shared with 0106's own-message kind if that lands first).
