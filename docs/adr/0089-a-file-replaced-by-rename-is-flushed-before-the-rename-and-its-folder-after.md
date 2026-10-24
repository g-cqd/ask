---
status: accepted
date: 2026-10-24
---

# 0089 — A file replaced by rename is flushed before the rename and its folder after

## Context

A second analysis pass of ask (`ask-formal-report/REPORT.md`) ran `fcheck` over the code and found the same `replace-not-durable` warning
in three production writers, the rest being test fixtures: replacing a file by writing a new one beside it and renaming it over the old
one is crash-safe only if the new bytes reach the disk before the rename, and the rename before the caller is told.

| Writer | What it did |
|---|---|
| `AtomicFile` (credentials, aliases, the model catalogue) | flushed the file with `fsync`, not the folder |
| `ProjectTrust` (which project configuration the user trusted) | flushed nothing |
| `ScopedFile.write` (the agent's file write, ADR-0085, written in this session) | flushed nothing |

A crash could leave an empty file (the bytes lost, the rename kept) or bring the old one back (the rename lost). For the credentials
that is a lost sign-in, for the trust store a repeated `ask trust` or a file that is not what the user saw, and for the agent's
write a tool result that said "Wrote N bytes" for a file that was not there after a power cut.

## Decision

1. **The barrier, on both.** The new file is flushed with `F_BARRIERFSYNC` before the rename, and the folder with the same call after it.
   Plain `fsync` on macOS does not make the drive order its writes, so it can leave a rename that survived a crash its bytes did not,
   which is the whole hazard (ADR-0017 says the same for sessions). `FileFlush.barrier` is `AemiIO`'s `.barrier`, including its fallback
   to `fsync` where the call is not supported, in `AskAI` because `AskAI` depends on nothing else.
2. **Not `F_FULLFSYNC`.** Measured here, a replace of a 2 KB file takes 0.105 ms with no flush, 0.12 ms with `fsync`, 0.47 ms with the
   barrier on the file and the folder, and 6.0 ms with `F_FULLFSYNC`, which alone is more than the 5 ms action budget. The barrier adds
   about 0.35 ms.
3. **A failed flush is reported.** A failed file flush removes the temporary file and leaves the old one; a failed folder flush after
   the rename reports the failure and cannot undo the rename. The model is told ("could not be flushed") and may write again.
4. **One path for the trust store.** `ProjectTrust` now uses `AtomicFile` instead of a second copy of the same idea; its temporary name
   changes from `<file>.tmp` to a unique hidden name, as the other users of `AtomicFile` already have.
5. **The flush is a parameter** only tests give, so they can see when it happens and make it fail.

## Not changed

`SessionFile` already flushes both ways (`SessionFileIO.flushDirectory`). The four test files `fcheck` also named are fixtures. The
`fsync` fallback inside `FileFlush.barrier` cannot be exercised on APFS, which supports the barrier.

## Probes

Tests for each writer that record every flush with the state of the target at that moment (the bytes while the old file is still there,
the folder once the new one is) and that make each flush fail; a test of `FileFlush` itself; thirteen compiling mutants, twelve caught and
one equivalent. Not probed with the real binary: a crash in the middle of a write cannot be produced from outside the process.
