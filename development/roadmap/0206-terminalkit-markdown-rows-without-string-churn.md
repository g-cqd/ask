---
status: in-progress
blocked-by: []
date: 2026-11-04
---

# 0206 — TerminalKit's Markdown rows without String churn: byte-range runs, style ids, ASCII fast paths

A profile of TerminalKitMarkdown drawing every block of a 1 MB document (diary 2026-11-04, claim 14) puts **40% of the main thread in the Swift runtime** (reference counting, bridging, array copies) and **13% in malloc and free**, against 41% in our own code: row wrapping 12%, display width 3.5%, grapheme breaking about 3%.
Laying out every block of a 103 KB document takes 7.8 ms against 0.96 ms to parse it, so the renderer is where the largest factor is. ask's transcript, the viewer's terminal mode and the live edit loop (0203) all draw through it.

## What is built

- **Rows as byte ranges and style ids.** A row is a short table of runs, each (source range or constant-string id, style id), in one arena per block; a plain run names its bytes in the document, as ADR-0033 already says a run names its source, and chrome (bars, bullets, gutters) is a table of constants. A decoded entity or an expanded tab is the only run that owns text.
  The existing `StyledLine` stays as an adapter until ask has moved over, so nothing breaks, and its tests are the oracle of the new rows.
- **ASCII fast paths.** A run of all-ASCII bytes (a SIMD check) needs no grapheme breaking and no width table: its width is its length. Word wrapping finds break points on bytes and counts columns; the `String` path remains for the rest.
- **Rows keyed by what they depend on.** A block's rows depend on the width only down to its natural width: a paragraph of 60 columns has the same rows at 80 and at 200, so a resize reuses them; the cache key is (content hash from 0203 or the events as today, the width the block really used, theme, softbreak mode).
- **Local relayout, wherever the edit is.** Today every delta, and every edit, lays the whole block out again: 181 µs at 20 KB and 1.14 ms at 100 KB for a paragraph with no break (diary claim 15), so streaming one is quadratic. Instead: keep the rows before the edit's row (one earlier when text was removed), wrap again from there, and **stop when a row break falls where an old one did, shifted by the edit's length, and the styles after it are unchanged**: the later rows are kept and only their position moves. A stream at the end is the case where nothing follows; an edit in the middle or at the start reflows the few rows it changes; a changed inline delimiter restyles up to its match, found by comparing the inline tapes.
  Target: O(the rows that reflow), tested over the position series of 0203.
- Interned style ids (TerminalKit ADR-0021 already makes them process-wide), so a run carries one integer.
- ask's `MarkdownRowCache` moves onto the new rows and the content-hash key once 0203 lands.

## Measured

Release, quiet machine, median and spread: every block of the 103 KB and 1 MB documents, one changed block, a resize, allocations per block (target: one arena, no `String`), resident bytes per 1000 rows; ask's budgets (input delay, action to action, memory) before and after.
Hypothesis to test: at least 3 times faster for every block, an order of magnitude fewer allocations. The profile says where the rest goes; experiments are kept or reverted by their numbers, as in 0205.

## Red first

The new rows equal the old rows for every Markdown example of AemiMarkdown's suites and the property tests of TerminalKit's renderer (width never exceeded, every source byte shown once, selection maps to source); the allocation ceilings of TerminalKit's markdown suite tighten; a resize reuses rows (counted).

## Done when

TerminalKit's markdown suites and gates pass in release, ask draws through the new rows within its budgets, `StyledLine` is either gone or a thin adapter with a stated end of life, and the numbers are in the diary and an ADR.

## Not in scope

The screen buffer and its flush (already proportional to the change, TerminalKit ADR-0008), a new theme model, Markdown features.

## Rule from the owner (2026-11-04)

ask's screen composer may change only if performance, reliability, resilience, efficiency and correctness are guaranteed for all existing tests and the new ones. What is generic in the change goes to TerminalKit (`TerminalKitMarkdown`); `UnicodeWidth` moves to `AemiUnicode` if a second consumer (AemiMermaid's text backend) needs it.

## Progress (2026-11-04)

Baseline and probe: `MarkdownRowsProbe` in TerminalKit's Benchmarks package (public corpus, CPU time, instructions, allocations): 450 instructions and 170 to 200 allocations per source byte-KB at 80 columns, about six times the parse (diary 2026-11-04-02, claim 24). Kept so far: the theme read through one object and no prefix machinery outside containers (-15 to -20% instructions); allocations unchanged. Left: the redesign (rows as ranges and style ids, ASCII fast paths in the wrapper, rows keyed by natural width, local relayout of a changed block) and ask's screen composer on the new rows, under the owner's rule above.

