---
status: in-progress
blocked-by: []
date: 2026-11-04
---

# 0202 — A zero-copy fence reader in AemiMarkdown

Four consumers each collect a fenced block's language and lines: TerminalKitMarkdown (`CodeBlock` does it today), ask (its own `CodeFence.scan` rescans the text for fences and finds a block's fence again from its source line, because a block "holds no range of its own"), the viewer kit (0199) and the
Quick Look extension (0201). The second consumer is the reason to put it in the parser's package once. AemiMarkdown stays free of rendering and of Mermaid (ADR-0001, decision 1):
this only reads what the tapes already hold (`codeBlock`, `infoString`, `codeLine`). Design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 4.

## What

- `MarkdownFence`: whether the block is fenced or indented, the info string's byte range, the first word of it (the language) as a range, and the line ranges, with the spaces a tab left
  before each line. Read from `MarkdownDocument.events(of:)` for one block; no copy of text, no allocation once the reader is warm.
- A reusable reader value, like `MarkdownEvents.restart(at:in:)`, so a renderer keeps one.
- TerminalKit's `CodeBlock` moves onto it (a refactor in its own commit, behaviour pinned by the existing renderer tests), and ask's fence search moves onto it with 0198 (`CodeFence.scan` keeps only what folding needs).

## Red first

A test per behaviour: a backtick fence, a tilde fence, an info string with attributes after the language (`mermaid title="x"`), an unclosed fence at end of input, an indented block,
a fence inside a list item and inside a quote (the container prefix is not in the lines), an entity or backslash in the info string, a tab-indented line. An allocation ceiling with `CAemiTestKitMalloc`.
Streamed one byte at a time, the lines of a final block never change (as `BlockIdentityTests` does for events).

## Done when

The reader is public and documented (DocC, tested examples), AemiMarkdown's suites and gates pass in release, the benchmark of the event walk is unchanged (median and spread, before and after), and TerminalKit uses it.

## Not in scope

Recognising Mermaid, or any other language, in the parser; reading a block's markers (ADR-0002 leaves a block source range until a consumer asks).

## Progress (2026-11-04)

`MarkdownFenceReader` is built in AemiMarkdown: top-level blocks by `read(_:in:)` (style, info, language, closed or not from the block's source range) and nested ones from events (`isClosed` nil), reused lines array, 15 tests including every specification example's code. Left: the allocation ceiling with `CAemiTestKitMalloc`, DocC, the TerminalKit `CodeBlock` migration and ask's `CodeFence.scan` (own commits).
