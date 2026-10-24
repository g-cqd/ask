---
status: accepted
date: 2026-10-23
---

# 0068 — A host copy is pending until its command has exited

## Context

ADR-0056 made copy feedback honest about what was *requested*: a terminal write is **sent** (OSC 52 has no reply), and host pasteboard
work was **queued**. "Queued" was where the information stopped: `pbcopy` was started on a detached task and nothing watched it end,
so a failed or hung command left the status line saying a copy was in flight forever, and a command that exited before reading its
input would have killed ask with SIGPIPE on the write.

## Decision

- The pasteboard is a command whose **exit decides the copy**: status 0 is *copied*; a non-zero status, a command that cannot start, or
  one still running after five seconds (it is then terminated) is *failed*, with the reason in words. A deadline and the exit both
  resume one continuation; the first wins, no thread waits, and the text is written on its own thread so a large text cannot deadlock a
  pipe the command has not started to read.
- The write end of the pipe has `F_SETNOSIGPIPE`, so a command that exits without reading gives the write an error, not a signal.
- The status line shows what is known when it is known. Terminal route: *Copy sent to terminal*, never "copied". Host route: *Host copy
  pending*, then *Copied to host clipboard* or *Host copy failed: …*. Both routes combine in one notice (*Copy sent to terminal;
  copied to host clipboard*); a failed terminal write stays in the notice beside a successful host copy.
- A result is applied to the copy it belongs to. Each copy has a number; a late result of an earlier copy is dropped. If the user has
  cleared the notice, a success stays cleared and a **failure is shown anyway**: a copy that did not work must not vanish with the
  highlight.
- `ScreenSession` moved to its own file (a pure move) to keep both files under the structure ceiling.

## Consequences

The terminal route remains unacknowledged by design; nothing in ask claims a terminal copy arrived. Reporting a host copy as *copied*
means the command exited 0, not that another application has read the pasteboard. The real `/usr/bin/pbcopy` is not exercised by
tests, because doing so would overwrite the user's clipboard; the same runner is exercised with real processes (`sh`, `false`, `sleep`,
`true`). A pasteboard command other than `pbcopy` (such as `wl-copy`) would reuse the same runner.
