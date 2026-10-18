---
status: not-started
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

## Done when

A session written by one run is read by the next, a branch reconstructs correctly, and a compaction
entry leaves the tree intact.

## Notes

Not blocked by anything. `AskCore` already reaches `FileManager`, and `public import Foundation` is
already in place for SE-0409.