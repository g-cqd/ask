---
status: in-progress
blocked-by: []
date: 2026-11-04
---

# 0203 — AemiMarkdown: edits at typing speed, with block source ranges, content hashes and change sets

The owner (2026-11-04): a user edits a Markdown file and the render follows at the same time, sub-10 ms, by block, in SwiftUI and in the terminal. Today's parser only grows (ADR-0001) and a block's identity is its tape index (ADR-0002), which shifts when a block appears above.
Measured today (diary 2026-11-04-01, claim 10): reparse everything and render only the changed block reaches rows in 1.4 ms at 103 KB and 16 ms at 1 MB; a consumer's own hash of each block costs half the parse again. Design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 7. An ADR (0003) records the decision.

## What is built

1. **Block source ranges and content hashes**, recorded as each top-level block closes: the range of its bytes (the thing ADR-0002 deferred until a consumer asked: the viewer's copy, the editor's scroll sync and the diff are three), and an XXH64 of those bytes mixed with what its links resolved to
   (a hash of each destination, a marker for an unresolved label). Positional things such as footnote numbers are the renderer's. A renderer's cache is keyed by (content hash, width, typography, theme): identical blocks share an entry, a moved block hits, no identity bookkeeping.
2. **Walk from an ordinal.** `block(at:)` and a block sequence that starts at a given ordinal, so a host after a stream delta begins at the first non-final block instead of block 0 (today O(blocks) per delta: 13 µs at 569 blocks, 84 µs at 3592, diary claim 15).
3. **`replace(_ range:, with:)` returning a `MarkdownChange`**: the first block that differs, how many old blocks became how many new ones, and the unchanged suffix, by comparing hashes from both ends.
4. **Phase A first**: reparse from the changed block's restart point to the end and reconcile by hash. It is the oracle and is enough to about 400 KB. **Phase B second**: restart at the block that holds the edit (or the one before it, where a lazy continuation, a setext underline or a list reaches back) with an empty container stack, parse forward until a top-level block start coincides, shifted by the edit,
   with an old one and nothing is open, then splice the new slots into the tapes and add the length difference to the offsets after it. O(edit region + distance to resync + the tail move), except where an edit changes everything below (an opened fence resyncs at its close, or never: O(tail), no worse than a full parse).
5. **Cross-block dependencies**: per label, the blocks that used it, resolved or not; changing a definition re-runs the inline phase of those blocks only and changes their hashes. Documented difference from streaming (ADR-0001, decision 4): an edit applies a definition to every use, as a whole parse does.

## Order, by what this machine holds (diary claim 13)

Of 22,478 Markdown files on the development machine the median is 3 KB, the p99 is 54 KB, the largest is 719 KB (a changelog), and 5 are over 400 KB. **Phase A and the content hashes cover every file that is edited by hand**; phase B serves documents that are not written by hand
(generated logs and changelogs, a long transcript) and is the larger risk. So items 1 and 2 and phase A land first, and phase B is started only when a measurement on a real large document (the changelogs, a long session) shows phase A missing the budget there. This is a plan, not a cut: B stays in the entry.

## An edit is anywhere

The owner (2026-11-04): an edit is not always at the end; it can be in the middle or at the start. The costs that depend on position are the move of everything after the edit: measured on a stand-in for the tapes of a 1 MB document, an edit at the start costs about 0.18 ms (the shift of 58,690 slots by a class table 88 µs, a `switch` per slot 459 µs; the tape splice 21 µs; the source move 62 µs), at the end nothing (diary entry 02, claim 16).
So the shift is driven by a per-(tag, kind) class table, not a `switch`, and the tests, benchmarks and the latency script carry a **position series**: the start, the first block, a quarter, the middle, three quarters, the last block, the end, a block boundary, inside a fence, a table and a list; and the operations insert, delete, replace, split a paragraph, join two, paste 10 KB, cut a block, paste a megabyte at the start.
`MarkdownChange` also carries what a caret or selection needs to survive it (the ordinal shift of every block after the change and the replaced range, so an anchor snaps to the nearest new block). An external change (a file saved elsewhere) is a diff of old and new bytes split into hunks, by Aemi's diff, applied from the last hunk to the first.

## Red first

- **The differential test that makes phase B safe**: for every CommonMark and GFM example (682) and for the corpus, every single-byte insertion, deletion and replacement at every position, and random multi-byte edits, the edited document equals a fresh parse: tapes, hashes and diagnostics. Written and seen failing before B exists (against a deliberately wrong resync).
- The differential test and the bound test run over the position series above, not only over every byte position of the small examples; a cost that depends on position is reported as a slope.
- A bound test counts the work of an edit against the size of the edit (an edit in the middle of a 5 MB document does work proportional to its blocks); an allocation ceiling per edit once warm (`CAemiTestKitMalloc`); the limits of `MarkdownLimits` hold under edits; an edit never fails.
- Streaming still passes `BlockIdentityTests`; a streamed document and the same document edited into place have the same hashes.

## Measured

Release, quiet machine, median and spread, at 23 KB, 103 KB, 1 MB and 5 MB: the edit to the changed set, phase A and phase B, before and after (the scratch probe of the diary is the baseline); the cost of the hash inside the parser against the consumer-side walk. The target is an edit within 4 ms p99 at every size (1 ms at 1 MB is expected for B); where A stops meeting it sets the size at which B is used.

## Done when

AemiMarkdown's suites and gates pass in release, the differential test passes, the parse and streaming benchmarks are unchanged within noise (they gain a hash per block), DocC and the README describe the API, and TerminalKit's renderer and the viewer kit (0199) cache by content hash.

## Not in scope

An undo history, collaborative editing, edits from several places in one call (a loop of `replace`), editing a document while a stream is appending to it.

## Progress (2026-11-04)

Built and measured, in AemiMarkdown: block source range, XXH64 content hash (with what the block's reference links resolved to) and ordinal; `blockCount`, `block(at:)`, `blocks(from:)`, `blockOrdinal(containing:)`; `MarkdownEditor` with `replace(_:with:)` returning a `MarkdownChange` (first block, removed, inserted, byte and block shift, ordinal and offset mapping), by **restart and resync** (phase B) with the whole parse (phase A) as the fallback and the oracle: a definition came, went or moved in the region, a diagnostic, or the size limit. The tape splice is a table-driven shift (`TapeShift`), and a block's range and hash were fixed where the differential test showed them wrong (unclosed fences and HTML blocks own their blank lines; an edit on a block's first two lines restarts at the block above).
Tests: every specification example at every position with 13 insertions, deletions and replacements (about 300,000 edits) and six seeds of 2,500 random edits, each compared with a fresh parse tape for tape; a large document at 15 positions; a bound test (the region read is a block or two). TLA+ `EditResync` states the restart rule and fails without it. Diary 2026-11-04-02, claims 19 to 22: an edit costs 0.07 to 4.8 million instructions (6 to 252 µs) at 23 KB to 5 MB where the whole parse costs 1.8 to 367 million.
Left: an allocation ceiling per edit once warm (about 13 now); streamed and edited documents compared on hashes (typed-in-order is tested); a reference multimap so that an edit to a definition re-runs only the blocks that use it, instead of the whole parse; external changes as hunks by `AemiDiff`; the cost of the whole-parse fallback on documents with many definitions; DocC and README. Reuse: `AemiIO.RawFileMap` for mapped sources, `AemiIO.FileWatching` for the app, `AemiRuntime.ScratchPool` for parallel work.
