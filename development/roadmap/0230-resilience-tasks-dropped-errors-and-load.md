---
status: in-progress
blocked-by: []
date: 2026-11-13
---

# 0230 — Resilience: background tasks, dropped write errors, the screen under load

Engineering plan phase C, the owner's choices of 2026-11-13 (a gate rule for `try?`).

1. Every unstructured `Task {}` and `Task.detached` (110, 2026-11-13) audited: what it captures (weakly when it outlives a session),
   who cancels it, what it races. A session's tasks become children of a per-session group cancelled on switch; a test per
   lifecycle event that none of the old session's is left.
2. The 35 `try?` around writes: each surfaced (a notice, a retry) or justified with a `// try?:` reason. The gate refuses a new
   `try?` around a write without one.
3. Under load (notes n18, n55): a probe mode with artificial CPU load for the input path, and the input loop's priority checked.

## Done when

The audit table is in the diary, the gate rule is on, and the input probes pass under load.

## Part 2 done (2026-11-13): dropped write errors

The gate: `DroppedWriteErrorsTests` (AskCoreTests) scans `Sources` for `try?` before a call that keeps data (`recordThread`, `record`,
`save…`, `write(to:`, `writeAll`, `copyItem`, `moveItem`, `remember`, `put`, `renewMCP`); each needs `// try?: why` on its line or
above. Closing, removing a temporary and terminal writes are outside it. It fired on 17 sites.

Said to the person now, where it was dropped: a thread's start, identity, merge and name and the conversation's name
(`saveThreadRecord`: "it will be missing after a resume"); a fork's task list and notes that could not be copied (`copyForFork`
throws; the fork stands); the session key not kept in the keychain; keys that could not be created; the first-start encryption choice
not saved. Given their reason (10): credentials held for a retry, the search index (a cache), a picture kept inline, a job's file
marked full, reload grants, a remembered account, a renewal reported to its caller.

Tests: `SavedRecordsTests` (the fork's notice; red with the notice removed), `TaskBoardTests` (the copy throws).

## Left

Part 1 (the 110 unstructured tasks) and part 3 (the input path under load).
