---
status: accepted
date: 2026-11-04
---

# 0145 — A closed mermaid fence is drawn as a diagram in the transcript

Extends ADR-0046 (assistant messages as Markdown, long fences folded) and roadmap 0065 (the Markdown renderer). Roadmaps 0066 and 0198.

## Context

Assistants answer with Mermaid diagrams in fenced blocks. The transcript showed them as code. Six existing renderers were surveyed (the research note of 2026-11-04): all pass escape
and bell bytes from a label through to the terminal, none bounds nesting, and four cost more than linear time in the size of the diagram. A diagram is untrusted input that a model
chose, drawn into the owner's terminal.

## Decision

1. **Our own engine, AemiMermaid.** UTF-8 in, flat arrays out, no recursion, limits on source, nodes, edges, labels, nesting and virtual nodes (`MermaidLimits.terminal`: 500 nodes, 2000
   edges), at most sixteen diagnostics. Labels are cleaned when read (controls, C1, bidirectional controls, invalid UTF-8) and the cell writer cleans again. The other renderers are
   oracles run from scripts, never dependencies.
2. **Drawn when the fence closes.** `MermaidRows` takes a top-level block that `MarkdownFenceReader` says is a closed `mermaid` fence and draws the diagram in its place, in the
   transcript's width, with the width function of TerminalKit's `UnicodeWidth`, and the theme's style for each role (text for nodes, the rule's for lines and frames, the quote's for
   notes). While the fence streams it is the code block it was; the diagram appears when the closing fence arrives.
3. **Falling back is the normal way to fail.** A source the engine cannot read (an unknown kind, a limit passed), a diagram too wide for any layout (it turns left to right into top
   down, wraps its labels to 24, 16, 10 columns, then is refused), or any other language, stays the code block with its folding and its highlighting. Nothing is dropped.
4. **The row cache is untouched.** The rows are a function of the block's events and the width, which the cache already keys on.
5. **Not in this decision:** a selection over a diagram copies nothing (the rows are chrome: the source map is per line and a diagram has no line-for-line source); toggling between
   the diagram and its source; state, class, ER, pie and Gantt diagrams; a setting to turn diagrams off (they follow `ui.markdown`).

## Consequences

AskTUI depends on AemiMermaidSyntax, Scene, Layout and Text. Reading, laying out and drawing a 100-byte flowchart takes about 50 µs, well inside the 8 ms action budget, and runs when
a block is laid out, not when it is drawn, so scrolling costs nothing. The engine, its tests (a width sweep from 1 to 120, a mutation fuzz, a growth test) and its limits are in AemiMermaid.
Until its repository and AemiMarkdown's are pushed, ask resolves both by path and `BenchmarkDependencyTests` fails for want of revisions; `Scripts/update-pins.py` moves the pins afterwards.
