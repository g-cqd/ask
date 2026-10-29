---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0086 — Finish AemiMarkdown and use it in ask

The owner, 2026-10-28: AemiMarkdown should be finished. It is the parser behind roadmap 0065 (Markdown in the transcript).

## Where it stands (read 2026-10-28, not run)

`g-cqd/AemiMarkdown`, last commit 5377e08, pushed to `origin/main`. Its README says "Status: under construction"; it has one ADR
(0001) and one diary entry. It parses to two flat tapes (blocks, inlines) over UTF-8, CommonMark 0.31.2 plus the GFM extensions
(tables, strikethrough, autolinks, task lists, footnotes, alerts, math), with streaming snapshots and incremental open-leaf
parsing (the last commit). 0065's record of 652/652 spec examples, 11x throughput and 10 allocations per streamed delta is from
2026-10-25 and has not been re-measured here.

## What "finished" means (from 0065, "Still owed in this phase", and the README)

- DocC for the public surface (the diary says it is not built); the static analysers (deadwood, dolly, fcheck) and the structure
  gates the other Aemi packages carry.
- Re-run conformance and the benchmarks on the current revision, and record them. 0065's numbers predate the last three commits.
- Set-scan kernel and SIMD skipping of plain text: only if a measurement shows the scan is the ceiling (0065 says it is not).
- Footnotes, task lists and the tag filter: the README now claims footnotes and task lists; check that against the ratchet.
- The licence question for spec fixtures (CC BY-SA 4.0): store attributed fixtures or generate expected output from cmark at test
  time. The owner has not answered.
- Replace the "under construction" status with the actual one.

## What ask then does (0065 phases 2 to 5)

- Add AemiMarkdown to ask's `Package.swift` at one pin (TerminalKit ADR-0005 rule), and the renderer: headings, lists, tables,
  fences, inline code, links, with `ui.markdown`.
- The decisions 0065 still owes as ADRs before phase 3: copy semantics (the Markdown source), link safety (scheme allowlist,
  control characters refused, target shown when it differs from the text, a click opens only by user action), and the Aemi pin.
- Highlighting inside fences uses AtelierLexers once promoted (0087).
- Not in scope here: Mermaid (0066), the prompt editor's colouring (0085).

## Done when

AemiMarkdown carries DocC, its gates and a current benchmark record, its README says what it is, and ask renders an answer through
it behind `ui.markdown` with the three ADRs written.

## Owner's decisions (2026-10-29)

- The licence of the spec fixtures: respect it. AemiMarkdown itself is MIT; the CommonMark and GFM spec fixtures stay as attributed copies
  under their own licence (CC BY-SA 4.0), and the README gains a notice listing everything distributed in the repository under a
  different licence than the package's.
- TerminalKit's features are consolidated first (the palette and theme, scroll state, the closing of 0016 to 0019, the markdown renderer's
  place), then AemiMarkdown is finished.
