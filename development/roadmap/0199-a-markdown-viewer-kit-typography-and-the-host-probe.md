---
status: not-started
blocked-by: ["0202", "0203", "0207"]
date: 2026-11-04
---

# 0199 — A Markdown viewer kit in `AemiMarkdown/Apps/MarkdownLook`: system-font typography, vector drawing, and a probe to choose its host

The viewer half of the owner's request (2026-11-04): a SwiftUI and AppKit renderer of AemiMarkdown's blocks, in system fonts, with typographic care, no third-party package, linear time. It lives for now in `AemiMarkdown/Apps/MarkdownLook`
as `MarkdownLookKit`, a library in a sub-package of its own (like `Benchmarks/MarkdownBench`), extractable later. Design: `development/research/mermaid-markdown-quicklook-2026-11.md`, sections 6 to 9.

## Phase 0: two probes, then choose

- **Typography samples.** Render sample documents (headings of every level, tight and loose lists, nested lists, a quote, code, a table with numbers, a diagram placeholder) at the **default of 13 pt (Apple's body style, 16 pt line)** and the reading steps 15 and 17, with prose leading at the **decided 1.4 em**, 1x and 2x, light and dark, from the proposed `Typography` tokens, to PNG; the owner judges by eye and
  fixes the leading, the heading mapping, the measure and the spacing. The default size is already decided: Apple's body (diary 2026-11-04-01, claim 9). Smart punctuation is on in the viewers (decided), and is checked on the samples for apostrophes, quotes around digits and code.
- **The host, in the lab (0207).** Skeletons of (a) per-block SwiftUI views in a lazy stack with `Equatable` identity, (b) one TextKit 2 view with attachments and (c) an own windowed layout (a CoreText frame per block cached by content hash, a prefix-sum tree of heights, only visible blocks drawn, behind a SwiftUI view), measured in release:
  **edit and stream latency, p50 and p99, at 100 KB, 1 MB and 5 MB, and a 100 KB paragraph streamed in 40-byte deltas** (the numbers that decide; a full redraw of the viewport costs 6.4 ms in software CoreGraphics and a repaint of one changed block 0.18 ms, diary claim 15, so a host that cannot repaint a dirty rectangle starts behind; the scratch probe gives TextKit 2 1.7 to 5.4 ms p50 and a 31 to 39 ms tail, CoreText 0.16 ms per block, diary claims 11 and 12), first screen, scroll hitches, resident memory, and a 100 KB answer streamed in 40-byte deltas.
  Median and spread, quiet machine. The choice and the numbers go in the diary and an ADR. The public API is SwiftUI whichever host wins; (c) must also bring selection, find and accessibility, and the probe says what that costs.

## What is built

- A block model from the tapes: per top-level block, cached **by content hash** (0203), one attributed string (the one copy at the edge) and chrome descriptors; only a changed block is laid out again, whether it was streamed or edited. A prefix-sum tree of heights and a scroll anchor so nothing jumps. No recursion: containers are an explicit stack; every pass over a document is linear in its size.
- **Selection copies Markdown source** (decided 2026-11-04): every run carries the source range it shows and copy writes those bytes (ADR-0033's rule); the reading size (13, 15, 17) is a setting persisted with the app's preferences.
- `Typography`: em-based tokens and role names, the system font only (text, monospaced, tabular figures), drawn at final size, no manual tracking, kerning on, weights measured; line heights, a grid unit of half a line, collapsing margins, measure of about 32 em, hanging list markers, hairlines snapped to the pixel grid, a balanced wrapper for headings, and monospace only where the research note lists it.
- Colour roles resolved to system semantic colours, so appearance and Increase Contrast follow without a new layout.
- Links by the scheme allowlist of ADR-0129 (a click opens only by user action), images local only and never from the network, highlighting from `AemiLexers` through roles.
- A hook for fenced blocks so 0200 can place a diagram; until then a mermaid fence is a code block.

- **Vector only, enforced**: no `drawingGroup`, `blur`, `shadow`, `compositingGroup` or material as content in the kit, by a source test (each rule checked by adding a violation once, as `SourceStandards` does); a test draws each sample document into a PDF context and counts image objects (zero, except images the document itself holds; the detector is first shown to fire on a bitmap).
- **Edits anywhere**: the position series of 0203 (start, middle, end, inside a fence, a table, a list; insert, delete, split, join, paste, cut) runs through the lab for every host; a selection or caret survives a change above it (the change set shifts the ordinals).
- **Long paragraphs**: a deterministic test (a count of the characters handed to line-break calls, with no wall clock) shows the total is within a small multiple of the paragraph's length for 3 KB, 30 KB and 1 MB paragraphs; a paragraph over a stated length has its own fuel and falls back to plain line chunking.
- **Zoom is lossless**: magnification scales laid-out content as a transform (no reflow, crisp at every level); the reading-size setting (13, 15, 17 and so on) re-lays the text out at its final point size. Both are persisted separately.

## Instant, not just fast

The ceiling is 4 ms p99, and the aim is the earliest frame: the event handled on arrival, no timer or debounce, no hop for a small document (parse, reconcile, layout and drawing in the same run-loop turn), the dirty rectangle of the changed block repainted and nothing else, fonts, attribute dictionaries and framesetters warmed so the first keystroke is not the slow one, **local relayout wherever the edit is** (lines before the edit kept, typeset again from there until a line break falls where an old one did, shifted, with unchanged styles after it; a stream at the end is the case where nothing follows) in **bounded windows**, because CoreText's line breaking costs O(the paragraph) per call: 1.6 ms at 3,000 characters, 71 ms at 10,000, 0.58 s at 30,000, 6.6 s at 100,000 (diary entry 02, claim 17), so a paragraph is never typeset in one call and a one-line 30 KB file cannot hang a preview; and the block walk started from the first non-final block. Each is an experiment kept or reverted by its number, measured from the event's own timestamp to the end of drawing, in the lab.

## Red first

Property tests on the typography (block tops on the grid, heading space above at least twice below, no line over 34 em outside code, tables and figures, no text under 10 pt, contrast of every role pair in both appearances at least 4.5 to 1 for text and 3 to 1 for strokes, a heading wraps at its own weight);
linear growth in document size; an allocation ceiling per block once warm; stream-versus-whole equality of the blocks; an edit leaves the cache entries of every other block untouched.

## Done when

A document, a stream and an edit render in the chosen host within the budgets the probe set (an edit within 4 ms p99 at the sizes of 0203), the samples were approved, and the tests above pass in release.

## Performance, by measurement (research note, section 13)

Block layouts cached by content hash and bounded by bytes, with heights only for evicted blocks; layout of the visible blocks in parallel on a small fixed pool, first screen first, with parse-ahead of the viewport; inlines parsed only for blocks that are drawn (0205, E5); an attributed string for a visible block only, built from an 8-bit string without copying where the bytes are ASCII; fonts, attribute dictionaries and colours resolved once per role and appearance and kept;
one drawing view that invalidates only the dirty rectangle of a changed block (an AppKit-backed drawing view gives that; a full-canvas redraw does not, so it is measured against it); no timer or display link while nothing moves; the file mapped, not copied (0205, E6). Each kept or reverted by its numbers.

## Not in scope

The editing pane and file watching (0204), math typesetting (shown as styled source), remote images, printing and export beyond what the CoreGraphics backend gives for free.
