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

## Part 1 done (2026-11-13): what background tasks hold

The count was wrong: 110 included the structured `addTask`. There are 72 unstructured tasks: 33 keep or return their handle, 2 are
awaited on the spot, 37 are started and left (AskTUI 15, AskSession 12, AskTools 7, AskMCP 2, AskAgentCore 1). Each of the 37 was
read for what it captures across a session switch:

- **Held a session (defects):** the conversation's naming (fixed 2026-11-13) and the search index update at a compaction: a session
  left right after a compaction stayed locked while its index was built. It now works from a snapshot of the entries.
- **Kept memory:** a session's search index stayed in memory for the life of the process; leaving a session now forgets it.
- **Hold no session:** a thread's naming, merge and stop (by name), the MCP sign-in, an opener's command, the goal's directive (50 ms),
  the git and forge refreshes (a path), the command dispatch, the screen's one-shot reads (files, skills, choices, clipboard,
  pictures), the jobs' watchers (weak). `KeepAwake`'s follower lives as long as the process, by design.

`SessionSwitchTests` holds the rule for the two that broke it: red on the code before each fix. A per-session task group was not
needed for these; it is the answer if a third one appears.

## Left

Part 3 (the input path under load).
