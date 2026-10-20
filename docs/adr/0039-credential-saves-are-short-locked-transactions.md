---
status: accepted
date: 2026-10-20
---

# 0039 — Credential saves are short locked transactions, and a refresh saves only if nothing changed

## Context

Every credential writer read the whole file, changed one record and renamed the result into place, with no lock. A refresh
token that rotates is spent by the refresh that uses it, so Codex already took a lock around read-refresh-save (ADR-0036);
nothing guarded the other writers, or the save itself. Named connections (roadmap 0046) put several accounts in this file, so
a lost update would sign one of them out.

## The probes

Ledger in `docs/diary/2026-10-20-30.md`.

- **Does the current code lose concurrent saves?** Eight concurrent `saveKey` calls for different providers kept one or two
  in all 20 rounds, with and without a file already present, and **no error was thrown**. **CONFIRMED.** In-process
  concurrency only; it shows the unlocked read-modify-write, and the cross-process claim rests on the next probe.
- **Does `flock` exclude another process, release on death, and conflict between descriptors of one process?** With a
  second process: exclusion yes; after `SIGKILL` of the holder, acquired; a second `open` in the same process conflicts.
  **CONFIRMED all three.** So a test with separate descriptors exercises the kernel rule that governs two processes, and a
  lock nested in one process would deadlock.

## Decision

1. **Two locks.** The refresh lock (`credentials.json.lock`, unchanged, so older asks still honour it) is held across a network
   call. A new save lock (`credentials.json.write.lock`) is held for one read, change and rename. The order is refresh then
   save; nothing takes them the other way, and neither is reentrant.
2. **One transaction for every writer**: login, logout, every save and removal, and the refresh's save. A read takes no lock
   and writes nothing: a rename is whole, so a reader sees the old file or the new one. A damaged or exposed file stops the
   transaction before anything changes.
3. **A refresh saves with compare-and-replace.** The replacement is stored only while the stored credentials are still the
   ones the refresh started from. If the user signed out, or in again, while the response was on its way, that stands: a
   removed sign-in is not brought back, and a new login is not replaced by an older grant's pair. The spent refresh token is
   not offered again.
4. **A save that cannot get the lock in 5 seconds says so** (`CredentialFileError.locked`) and writes nothing.
5. **Lock files are never unlinked**: removing one lets a waiter and a newcomer hold "the same" lock on different files.
   They are mode 0600 in the 0700 directory, opened `O_CLOEXEC` so `/reload` cannot leak a held lock.
6. **A lock is let go on release, on deallocation, and by the system when the process dies.**

## Consequences

- A save may wait for another ask's save, a few milliseconds in practice. The wait polls on the calling thread (2 ms), so a
  stalled holder can occupy a thread for up to 5 s. The refresh wait does not block a thread.
- The credentials directory now holds two small lock files beside `credentials.json`.
- **Not done here, and moved to roadmap 0046 where the schema is decided:** keeping top-level records this version does not
  know (an older ask saving would drop fields a newer one added), and a refresh lock per connection. Claude's refresh is
  still not locked across the network (0044 must first probe whether its tokens are single use); it does have the
  compare-and-replace.
- Older asks do not take the save lock, so an old and a new ask can still race on a save. They do still share the refresh
  lock. This matters only while both versions run.
- Cancelling a wait closes its descriptor, but no test pins that.
