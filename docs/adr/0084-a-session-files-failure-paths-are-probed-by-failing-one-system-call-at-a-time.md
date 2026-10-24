---
status: accepted
date: 2026-10-24
---

# 0084 — A session file's failure paths are probed by failing one system call at a time

## Context

`docs/formal/REPORT.md` listed three things in `SessionFile` that had been read and not probed: an unclosed descriptor when `begin`
fails, `.damaged` backups piling up when the rename after them fails, and a record that stays on disk after a failed flush. Each is a
failure that nothing exercised, because the file had one seam (the record write) and these are failures of other calls.

## Decision

1. **Every call a test may need to fail has a seam.** `SessionFileCalls` holds the record write, the flush, the rename and the lock
   adoption, defaulting to the real ones; the old record-write overload is kept on top of it. Nothing outside tests replaces them.
2. **A new session that cannot take its lock closes the file it made.** `begin` created the file and held its descriptor; when the
   duplicate or the lock failed, the descriptor was dropped open. Confirmed by asking the kernel which files the process had open (with
   a positive control for that check, which at first could not see anything and so proved nothing). It is closed on the way out; the
   file stays, because when the lock is taken by another process that process now owns it.
3. **A file is preserved once, however many times its rewrite is tried.** The original is hard-linked to `.damaged` (or `.version-N`)
   before the rename; when the rename failed, the next attempt linked it again as `-2`, `-3`, and so on up to a thousand, after which
   the session could no longer persist. Confirmed: four copies of the same bytes after three failures and a success. A backup that is
   already the same file (same device and inode) now counts as the original having been kept, and no new link is made. A later, different
   damage still gets its own numbered copy.
4. **A record whose flush failed stays on disk, and that is kept.** The bytes were written; memory rewinds them and tells the caller
   the change failed; the next change rewrites the file from memory and keeps the file that had the record as `.damaged`. Truncating
   the record away was the obvious "fix" and is not made: ADR-0013 says damaged bytes are never discarded, and a record that may
   already be durable is not ours to delete. The consequence is documented where it lives and pinned by a test: if ask exits before
   the next change, the session resumes with a message the caller had been told failed. That is the cost of a flush that fails after
   the write, and it errs toward keeping what the user did.

## Not decided here

Whether a failed flush should be retried in place, and whether the caller should be told that the record may nevertheless be there.

## Probes

Five tests, four of them failing exactly one call; the positive control for the descriptor check; eight compiling mutants, all caught.
