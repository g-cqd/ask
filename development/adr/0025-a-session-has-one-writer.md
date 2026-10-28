---
status: accepted
date: 2026-10-19
---

# 0025 — A session has one writer, enforced by a lock on its inode

## Context

Resume (`--continue`, `--resume`) makes it possible to open one session from two terminals. Two writers would
each append from their own in-memory tree. The file would then hold two interleaved branches that each process
believes is the whole session. The next damaged-file repair would rewrite one process's view over the other's
work.

The session file is replaced, not edited, when it is repaired (ADR-0017): a new inode takes the name by rename.
A lock tied to the first file opened would stop protecting the session after the first repair.

## Decision

`SessionFile` takes an exclusive, non-blocking `flock` when it creates or opens a session, and holds it until the
file closes (`SessionLock`).

- **Opening locks before reading,** so nothing can be appended between what is read and what is written.
- **A rewrite locks its replacement before renaming it into place,** then releases the old file. The name is
  never unlocked in between.
- **After locking, the descriptor's inode is compared with the path's.** A process that opened the old file
  just before a swap, then locked it after, holds a lock that guards nothing. It sees the mismatch and tries
  again, and the new file is held, so it fails as in use.
- **A second writer gets `SessionFileError.inUse` immediately.** It does not wait. "This session is open
  elsewhere" is the useful answer, and waiting would hang a `-p` script.

The concurrency rules ban in-process locks (`NSLock`, `os_unfair_lock`, `pthread_mutex`). `flock` is not one of
them: it orders separate processes, which no in-process primitive can do.

## Probes (`/tmp/flock-probe.py`, diary 2026-10-19-10)

On macOS 27.2, APFS:

| Case | Result |
|---|---|
| Another process, while the lock is held | refused (`EWOULDBLOCK`) |
| A second descriptor in the same process | refused (`EWOULDBLOCK`) |
| Replacement locked before the rename | the path stays locked |
| Holder killed by SIGKILL | released |

The same-process case matters for testing: the unit tests can prove the guarantee without spawning processes.
Because the kernel releases the lock when the holder dies, a crash cannot leave a stale lock. A pid or lock
file could.

## Alternatives rejected

- **A sibling `.lock` file.** It survives renames. But it leaves a file beside every session, and unlinking
  it opens a race, because a new inode would take the lock's name.
- **`fcntl` record locks.** They are released when *any* descriptor on the file closes in the process, so
  reading the file again elsewhere in ask would silently drop the lock.
- **Locking the project's session directory.** That makes one ask per project, not one writer per session.

## Cost (ADR-0016, `session/*` benchmarks, p50)

| Benchmark | Syscalls | Wall time |
|---|---|---|
| create | 3 → 6 | 55 µs, unchanged |
| open, 10 entries | 5 → 8 | 41 → 46 µs |
| open, 1,000 entries | 5 → 8 | 2.38 → 2.45 ms (within noise) |

The open reads the session through the lock's descriptor, which saved two syscalls; the first version opened
the file twice and cost 53 µs. The cost is paid once per run.

## Consequences

- A test or tool that wants to look at a session another `SessionFile` holds must read the bytes with
  `SessionLog`, not open it.
- Opening a session no longer "never writes anything" in the broad sense: it takes a lock. It still writes no
  bytes until the first change.
- One narrow race remains, and it is safe. Another `ask` could open a just-created file before its creator
  locks it. The creator then fails as in use rather than share the file.
