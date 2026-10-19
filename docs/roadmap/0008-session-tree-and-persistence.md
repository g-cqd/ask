---
status: done
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

Research behind the damage cases is in `docs/research/pi-1.3.0-findings.md`.

## Done — recovery is the default

`SessionLog.recover` opens sessions (ADR-0013): damage costs only what is damaged, every repair is
reported, and loading never writes. 16 recovery tests, 10 of 10 mutations caught. `decode` is a
strict wrapper over the same parser.

## Done — the file store

`SessionFile` (ADR-0017): one record per change, flushed with an ordering barrier before it counts, and
rewound if it cannot be persisted. The first change after damage rewrites beside the file and keeps the
original as `<name>.damaged[-n]`. Create and fork never overwrite. A change is O(1): 8–11 µs before the
flush at any session size, down from 1.86 ms at 100,000 entries. 19 tests; every compiling mutation of the
repair, undo and default paths was caught.

## Still owed

- **Placement**: where session files live, and how a session is named. Decided with the agent loop,
  which is the first thing that creates one.
- **A second writer**: two processes appending to one session. Needs a lock or a refusal, with a probe.
- Surfacing `issues` to the user, once there is a UI to surface them in.

## Done when

A session written by one run is read by the next, a branch reconstructs correctly, and a compaction
entry leaves the tree intact.

## Notes

Not blocked by anything. `AskAgentCore` does not import Foundation; files go through swift-system and
AemiIO.

## Decided with the loop (2026-10-18)

- **Placement:** `$XDG_STATE_HOME/ask/sessions/<project>/<UTC>-<hex>.jsonl`, else under `~/.local/state` (`SessionDirectory`).
- **A second writer:** every run creates a new file with `O_EXCL`, so two writers cannot share one. Resume, when it lands, takes a lock first.
- **Agent turns:** whole responses and tool results are persisted, with exact replay (thinking signatures included).

## Done — audit (2026-10-19)

Everything this entry asked for is delivered, and its last owed item is closed.

- **Resume** (0029) reads one run's session in the next, behind a writer lock (ADR-0025): the "second writer" item.
- **Placement and naming** were decided with the loop.
- **Compaction** is an entry that leaves the originals in the tree (0030, ADR-0026).
- **A damaged session is reported.** Opening one repairs it in memory (ADR-0013), and now says so: how many
  problems, the first three in words with their line numbers, and that the original is kept as a `.damaged` copy
  once anything is added. `-p` prints it on standard error and the screen shows it as a notice. Probe L (the real
  binary) cuts a session mid-record, resumes it, and checks the notice, the run, the byte-for-byte `.damaged` copy
  and both exchanges in the repaired file.
