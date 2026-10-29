---
status: accepted
date: 2026-10-29
---

# 0129 — Assistant messages are drawn as Markdown, block by block, and copied as written

## Context

Roadmap 0065 phase 4: the model's replies drawn as Markdown, on by default and switchable (`ui.markdown`), with a selection that copies the
Markdown source. AemiMarkdown parses (`2e75a94`); TerminalKitMarkdown lays out a top-level block into styled runs that name their source
bytes (TerminalKit ADR 0033); TerminalKit's `RowSegment` lets a row show several pieces of one hard line (ADR 0030, amended).

## Decision

1. Assistant items only, when `ui.markdown` is on (the default). Tool output, the user's prompt and thinking are drawn as before; with it off,
   a reply is drawn byte for byte as before (`PlainAssistantCharacterisationTests`, written first).
2. The parse is GFM plus alerts, **without math**: a reply that mentions two prices is not a formula.
3. A soft break is a line break (`SoftBreaks.lineBreak`): a model that ends a line means a new one. The first probe run caught it.
4. Each top-level block is laid out at the width, a blank row between blocks. Each run with a source becomes a `RowSegment`: hard line,
   grapheme offset, text. A selection maps cells to source positions through the segments and copies the item's own text; a drag that starts
   or ends at a hidden marker takes it, so `**bold**` copies whole.
5. A long fenced block folds as it does with Markdown off: one dim `code · swift · 30 lines` line, sharing the fence state and Ctrl+G. Open,
   that line stays above the code and a click on it folds the block; the fence markers themselves are not drawn.
6. Links: a hyperlink for `http`, `https` and `mailto`, and for `/` and `~/` paths (as `file://`, without a `:line[:column]` suffix); the
   target is written out when the text names another host. Bare paths in prose and in code spans are not linked with Markdown on.

## Consequences

- A streamed delta parses and lays out the whole reply again: 0.75 ms for a 9 KB reply, 3.7 ms for 58 KB (text: 0.14 and 0.67 ms). The
  largest reply in the owner's 12 MB session is 8.8 KB. Caching the rows of final blocks (by block, width, style and fold state) is the
  next step if replies grow.
- On that session, interleaved against `047fdc2`: open unchanged, resident size +0.5 to 0.9 MiB, a page +0.3 ms, a resize +2 to 4 ms; cold
  start, idle and active memory, input and action within noise.
- Parsing runs in the composer on the main actor, not off it as 0065's rails asked; input delay did not move in the measurements.

Evidence: diary 2026-10-29 (1); roadmap 0065.
