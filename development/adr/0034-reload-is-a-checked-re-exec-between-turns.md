---
status: accepted
date: 2026-10-19
---

# 0034 — Reload is a checked re-exec between turns

## Context

The user wants to develop ask from inside ask. That needs the running process replaced by a rebuilt one
without losing the conversation (`development/research/self-development-and-reload.md`; roadmap 0041). Hot-patching
code into a live process (Inject) was rejected there: Swift cannot unload code, it is debug-only, and ask's
state already lives in the session file.

## Decision

`/reload` replaces the process by `exec`, resuming the same session, in this order:

1. **Only a changed build counts.** `BinaryIdentity` is the executable's real path, inode, size and
   modification time, from one `stat`. A linker writes a new file, so the inode changes (probed in the research
   note). Hashing the 8 MB executable would put milliseconds on a cold start to answer what the file system
   already says.
2. **The user is told once that a build appeared.** `BinaryWatcher` is a kqueue on the executable's
   *directory*, because a rename-over is a directory event and the old file's own descriptor sees only a
   deletion. It runs from the start of the screen, on its own thread, through a `Conversation.background` seam
   so AskTUI imports no agent. It announces the first event and nothing more: a link raises several events as
   it writes, so the first means "a build appeared", not "it is finished".
3. **Jobs stop a reload.** `/reload` refuses while jobs run, naming them; `/reload now` stops them first. A
   reload that orphaned a dev server would be worse than refusing.
4. **The new build is checked before anything switches.** `ask --self-check`, run by the new binary with ten
   seconds to finish and its whole process group killed on timeout, loads this configuration with the new
   build's own parser and constructs the loop a run constructs, without a network. A build that fails is
   refused with its exit code and standard error, and ask stays where it is.
5. **The screen closes with a reason.** `ScreenExit.reload` is returned once the command's run has ended, after the
   last frame is drawn and the terminal restored.
6. **Then `exec`.** Every descriptor above 2 is marked close-on-exec first, whoever opened it, and the new
   build starts with `--resume <session>`, the flags as given, and `--reloaded-from` and `--reload-started`, so
   it says `Reloaded ask: built A → built B, in N ms`.

## Why restore the terminal before exec, not after

The research note found that raw mode survives `exec`. It does, and that is the problem: TerminalKit's
`enterRawMode` saves whatever `tcgetattr` returns at that moment as the settings to restore. A process that
inherited raw mode would save *raw* as its original and leave the user's shell raw on exit. Restoring first
costs one alternate-screen flicker and leaves nothing for the new process to get wrong. Probe H checks the
terminal is in line mode with echo after the reloaded process quits.

## Why sweep descriptors

The session file's `flock` (ADR-0025) belongs to an open file description. A descriptor that survived `exec`
would keep it, and the new process would find its own session locked by the process it replaced. The sweep
makes that impossible however the descriptor was opened. Removing the sweep fails probe H at "resuming the same
session".

## Security

`/reload` runs a binary: whatever is at the executable's path. The agent can write that file, so:
- only the user's typed `/reload` runs it, there is no tool for it, and the watcher only announces;
- the self-check runs it first, but a hostile binary can pass a self-check, so the self-check protects against
  mistakes, not against the agent;
- an automatic mode (reload when idle) must not exist until the sandbox keeps the agent from writing the
  executable, or until it asks the user each time. Roadmap 0041 says so.

## Cost (ADR-0016)

| | main | this |
|---|---|---|
| Cold start p50, 200 interleaved runs | 10.67 ms | 10.78 ms |
| Idle memory, medians of 15, twice | 8,912 and 8,896 KiB | 8,912 and 8,912 KiB |

The first version of the watcher used Foundation's `Thread` and raised idle memory by about 120 KiB (9,040 KiB).
With no watcher the figure was back at baseline, so the thread was the whole cost, and `pthread_create` with a 64 KiB stack
removed it. The budget itself (8,192 KiB) is already exceeded on `main` and tracked in roadmap 0007.

## Consequences

- A keystroke buffer and the scroll position do not survive a reload. `/reload` is typed, so the draft is
  empty at that moment; an automatic reload would have to carry it.
- An in-place rewrite of the executable (no new file) is not seen by the watcher. The linker does not do that.
- A descriptor leak in the watcher has no deterministic unit test: asserting a descriptor is invalid races
  with other tests that open files. `DirectoryWatch.close` reports that each `close` succeeded, which catches a
  double or missing close but not a skipped one.
