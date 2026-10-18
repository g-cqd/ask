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

## Done — the log codec

`SessionLog`: append-only JSON Lines, header plus one record per entry plus leaf records for checkouts.
Torn final lines, corrupt or blank lines, out-of-place headers, unknown versions, forward leaf references,
and oversized lines or archives are all reported, never skipped. The wire format is pinned by a literal.
22 tests, 11 of 11 compiling mutations caught.

These are deliberate divergences from pi 1.3.0, which silently drops torn and corrupt records, falls back
to the last entry for an unknown leaf, and truncates context at a missing parent. Probed by running pi's
own code; recorded in ADR-0012.

## Done — recovery is the default

`SessionLog.recover` opens sessions (ADR-0013): at least as convenient as pi 1.3.0 on every damage case
probed, never silent, never writing on load. 16 recovery tests, 10 of 10 mutations caught. `decode` is a
strict wrapper over the same parser.

## Still owed

- **The file store**: placement, one whole record per append call, and fsync policy, with its cost
  measured. On a session that needed repairs, keep the damaged original and write the repaired snapshot
  beside it, never over it.
- Surfacing `issues` to the user, once there is a UI to surface them in.
- Fork to a new file.

## Done when

A session written by one run is read by the next, a branch reconstructs correctly, and a compaction
entry leaves the tree intact.

## Notes

Not blocked by anything. `AskCore` already reaches `FileManager`, and `public import Foundation` is
already in place for SE-0409.