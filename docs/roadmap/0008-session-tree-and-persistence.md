---
status: in-progress
blocked-by:
date: 2026-10-18
---

# 0008 — Session tree and persistence

`ask` has no sessions. Every later phase reads from this, so it lands before the agent loop.

## The shape

pi models a session as a **tree**, not a list: JSONL entries, each with an ID and a parent, where the
current entry identifies the active branch. Continuing from an earlier entry creates another branch in
the same file; forking copies selected history into a new file. Model context is reconstructed from the
active branch alone.

That shape is worth copying rather than simplifying: it is what makes compaction, steering and
"return to an earlier point" cheap, and all three are wanted in a coding agent.

## What lands

- Append-only JSONL with stable entry IDs and parent references.
- Active-branch reconstruction, and context building from it.
- Branch creation from an arbitrary entry, and fork to a new file.
- Compaction as an entry that replaces older messages in subsequent requests, leaving the originals in
  the tree. pi's ordering rules for overflow recovery are worth reading before this is designed.

## Red TDD

Every entry type gets a round-trip test before the type exists. A session file that cannot be read back
is not persistence.

## Done — the in-memory tree

`SessionTree` in `AskCore`: append, branch from any entry, checkout (including a new root), fork of the
active branch with identifiers preserved, and context building that honours the latest compaction on
the active branch only. Every mutation is atomic: a thrown `SessionTreeError` leaves the tree equal to
its previous value, and the tests assert exactly that. Archive restoration validates identifiers
(nonempty, at most 128 UTF-8 bytes), duplicates, parent order, leaf existence and compaction boundaries.

Parents precede children, so cycles are unrepresentable and parent walks terminate. Fresh identifiers
skip ones a restored archive already holds.

22 tests. Nine compiling mutations — context ignoring compaction, older compactions replayed, foreign
boundaries, compaction-of-compaction, leaf not restored on failure, identifier overwrite, unseen parent,
unknown leaf, fork copying every branch — each turned the suite red.

The first draft's compaction test passed without ever creating a compaction: it compared `dropFirst()` of
an ordinary branch. Every context assertion now compares the whole list.

## Still owed — persistence

- Append-only JSONL with `Codable` added alongside round-trip tests, not before.
- Crash safety: a torn final line must be detected and reported, never silently dropped or half-read.
- Size bounds per line and per file; a hostile archive must not exhaust memory.
- Fork to a new file.

## Done when

A session written by one run is read by the next, a branch reconstructs correctly, and a compaction
entry leaves the tree intact.

## Notes

Not blocked by anything. `AskCore` already reaches `FileManager`, and `public import Foundation` is
already in place for SE-0409.