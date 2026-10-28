---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0111 — Prompt history with Up and Down

Owner wish (2026-10-28 19:22): Up and Down browse previous prompts so one can be reused. Once a recalled prompt is edited, moving to a more
recent one is no longer possible. `/` commands are included in the history.

## Still owed

- Where the history comes from: the session's prompts, and whether it spans sessions in the project.
- Up only recalls when the cursor is on the input's first row (Down on its last), so multi-line editing keeps its arrows.
- The edit rule exactly as asked: after an edit, Down does not go to newer entries; define what Down does then (nothing, or the draft).
- The draft being typed before browsing is kept and comes back at the newest end.
- Tests for recall, edit, multi-line inputs and commands.
