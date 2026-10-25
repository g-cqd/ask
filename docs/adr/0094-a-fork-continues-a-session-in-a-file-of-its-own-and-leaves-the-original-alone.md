---
status: accepted
date: 2026-10-25
---

# 0094 — A fork continues a session in a file of its own and leaves the original alone

## Context

ADR-0093 let a person go back to before a prompt inside a session; the other branch stays in the same file. Sometimes the person
wants the opposite: to try a direction without piling it into the session they will come back to, or to keep one session's branches
apart from another's. `SessionFile.fork(to:)` already wrote the active branch to a new file and nothing used it.

## Decision

1. **`/fork` continues this conversation in a new session.** The new file holds the active branch (the entries that led to where the
   session is now) and the strict sandbox the session last recorded, so resuming it keeps that sandbox (ADR-0045). The screen shows the
   same conversation and says which sessions are which.
2. **`/fork N` forks from before prompt N** (the numbers of `/tree`, ADR-0093) and puts that prompt back in the editor: the new
   session holds what came before it, and the next message goes on from there. The editor's draft rule is the same as `/tree`'s.
3. **The original is not touched.** The fork is written from a copy of the tree with the leaf moved, so the original's selected entry,
   its branches and its file stay exactly as they were (checked byte for byte, in the library and through the real binary). It stays
   saved and can be resumed.
4. **The switch follows `/resume`'s rules** (ADR-0041): only between turns, and refused while jobs run, because a session does not own
   processes; the model's narrowing does not carry into the new session; the old writer's lock is released and the new file holds its
   own. The new file's name comes from the same place as any new session's.
5. **Nothing is overwritten and nothing is half-made.** The destination must not exist, an unknown entry creates no file, and a failure
   before the file is complete leaves none.
6. **A fork is a session of its own**, with the real system calls; it does not inherit the original's.

## Consequences

Two sessions now share a history. They share nothing else: no later change to one reaches the other. A session listing shows both
under their own names, and neither records that it was forked; that is a possible later addition, not needed to use them.

## Probes

Unit tests for the fork (the active branch, an earlier entry, nothing, an unknown entry, an existing file, the lock, the sandbox record,
the recorder); eight compiling mutants, all caught (one needed rewriting because it did not compile). The real binary through a PTY with
a fake provider (`Scripts/probe-fork.py`): a fork of the whole conversation, a second from before a prompt, the files on disk, and the
requests the provider then receives, with a control that does not know the command.
