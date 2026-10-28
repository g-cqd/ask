---
status: done
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

## Result (2026-10-28)

`/continue` (listed in `/help` and the completion list) and the bare words `continue`, `resume`, `go ahead` and `go`, matched on the whole
trimmed input, case aside, send one fixed message, "Continue the work where you stopped."; it shows in the conversation as the user's message.
`/continue some words` appends them. A sentence that starts with a word is a prompt. While a turn runs it is queued like any message.
Tests: `ContinueTests`; real binary: `Scripts/probe-continue.py`. Side effect: the tests that pinned the command list and `/co` as a
three-command query were updated, and one test typed "go" and now types "hello".
