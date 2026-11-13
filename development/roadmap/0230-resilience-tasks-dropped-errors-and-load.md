---
status: done
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

## Part 3 done (2026-11-13): typing under load, measured; nothing to fix

`Scripts/measure-typing-under-load.py`: the time from a key written to ask's terminal to the read that carries that character back
(each key a character of its own), with a floor measured first (the terminal driver's echo through `/bin/cat`, 0.1 ms) and the
harness raised to the focal role, so the load does not hold the measuring back. On this machine (10 cores), 100 keys a row, twice:

| | median | p95 | worst |
|---|---|---|---|
| idle | 0.3 ms | 0.4 | 0.6 |
| every core busy (load x1) | 0.2 to 0.3 | 0.4 | 0.5 |
| ask's turn busy (a command flooding its block) | 0.3 | 0.5 | 0.8 |
| turn busy and load x4 | 0.3 | 0.3 | 0.5 |
| an 81 MB session resumed, idle | 0.3 to 0.6 | 0.8 | 1.1 |
| that session, a key right behind 40 wheel reports | 2.2 | 3.0 | 4.7 |
| behind 400 wheel reports | 6.2 | 8.1 | 8.6 |
| behind 400, load x4 | 6.9 | 10.8 | 13.3 |
| behind 2,000, load x4 | 25.4 | 30.2 | 34.6 |

The budget is 4 ms. A key waits about 13 to 15 microseconds per wheel report ahead of it on the longest session, under four times the
machine's cores in load: the stall of note n55 (0.5 to 0.9 ms a report, seconds for a fling) is gone and stays gone under load.
Found on the way: `measure-scroll-latency.py --busy` never answered the command's approval, so its turn was never busy; it answers
now. Not measured: a real terminal's own momentum events, and a turn busy on the long session (resuming it and sending a prompt
compacts first).
