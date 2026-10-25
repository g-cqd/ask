---
status: accepted
date: 2026-10-25
---

# 0102 — A watchdog outside ask stops an MCP server's process when ask is killed

## Context

ADR-0096 gives a stdio server a session of its own and stops it on every exit ask can see, with the input closed first and the signals
after a grace. ADR-0099 listed the exit it cannot see: SIGKILL and a crash, and said a server that ignores its input closing outlives
ask. ADR-0079 already solved this for jobs, which are also processes in sessions of their own: a shell outside ask, fed by a pipe,
stops every listed group when the pipe closes. A server is the same kind of thing.

## Decision

1. **A stdio transport reports its process to an observer** (`StdioProcessObserver`): `started(group:)` once the process exists, and
   `ended(group:)` after it has ended and been reaped, so a group id that may be used again is no longer listed. A program that could not
   be launched is never reported. `waitUntilRunning()` returns the process id once it is known, or nil if there will not be one.
2. **ask's observer lists the group with the jobs' watchdog.** The hub's standard transport is given the job table, whose watchdog is the
   one ADR-0079 describes: SIGTERM to each listed group when the pipe closes, two seconds, SIGKILL. One shell serves jobs and servers.
3. **Nothing changes when nothing is configured**: no server, no registration, and the watchdog's shell is started only at the first
   registration (ADR-0079), so an ask with no jobs and no servers still starts none.

## Consequences

SIGKILL, a crash and a signal exit of ask all stop the servers, including one that ignores its input closing and SIGTERM. The
coverage is the watchdog's: a pid-reuse window and the milliseconds before the shell starts are not covered (ADR-0079). The
guarantee is for servers ask started, not for what a server started in turn: those are in the server's session, so the group signal
reaches them only while they have not left it.

## Probes

| Claim | Result |
|---|---|
| A server that ignores its input closing and SIGTERM survives a parent that dies | `Scripts/probe-mcp.py` E, the control: the fixture in its stubborn mode outlived its parent's death and the close of its input |
| ask killed with SIGKILL while such a server runs does not leave it | probe E through the real binary and a fake provider: the server's process id (written by the server's own shell) was alive while ask was, ask exited with -9, and the server was gone within the watchdog's grace (8 s allowed) |
| The transport reports start and end, and never a launch that failed | `AskMCPTests`: the observer sees the pid while the process is alive and the end after it is gone; nothing for a program that does not exist |
| The hub lists and releases the group, and the shell stops a server that ignores everything | `AskToolsTests`: the group is on the list while the server runs and off it after; with the pipe closed the watchdog's shell stops a shell that ignores TERM and has closed its input |
| Compiling mutants | the start not told, the end not told, the group not watched, not released, the hub passing no observer: all caught. **Not run:** the real binary without the observer, because a build takes minutes; the control above shows the server would survive, and the mutant on the hub shows the observer is what stops it |
