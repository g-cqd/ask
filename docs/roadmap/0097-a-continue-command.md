---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0097 — A continue command

Owner wish (2026-10-28 16:51): `/continue`, and the bare words `continue`, `resume`, `go ahead` and `go`, tell the model to continue its
work.

## Plan

- Match the whole input only (trimmed, case-insensitive), so a sentence that starts with "go" is still a prompt.
- Send a fixed short instruction ("Continue the work where you stopped.") as a user turn; show it as the command typed.
- Works after an interruption (0083) and after a `maxTurns` stop (0098). Listed in `/help` and completion.
