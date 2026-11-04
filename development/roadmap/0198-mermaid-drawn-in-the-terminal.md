---
status: in-progress
blocked-by: ["0197", "0202"]
date: 2026-11-04
---

# 0198 — Mermaid drawn in the terminal: the cell backend, TerminalKit's fence hook and ask's adapter

The terminal half of 0066, on the engine of 0196 and 0197 (design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 5). 0066 keeps the owner's requirements (the toggle, copy gives the source,
limits, safety); this entry is the work that meets them.

## What is built

- `AemiMermaidText` (in AemiMermaid): a scene to rows of cells, each cell a scalar and a role. **A second sanitising layer at the cell**: nothing but printable scalars whose width the host's width function knows is ever written, so no escape sequence can come out of a diagram
  (all six renderers in the survey failed this). Box-drawing characters from sets `UnicodeWidth` agrees on (ambiguous widths: TerminalKit roadmap 0013), an ASCII mode, one blank row above and below. AemiMermaid never imports TerminalKit.
- **ask first, TerminalKit second.** ask already intercepts fenced blocks itself: `MarkdownMessageLayout` decides, per top-level block, whether a long fence is folded or open and puts a fold header in front of the rows. The diagram goes in the same place: a block whose language is `mermaid` (found through 0202's fence reader, which also retires `CodeFence.scan` and the `fence(of:events:)` search by source line)
  is drawn from the diagram cache, with the existing header row as the toggle. Once ask has proven it, the hook is promoted to TerminalKit as **`MarkdownFenceRenderer`**, a host-implemented protocol beside `MarkdownCodeHighlighter` (ADR-0033: the kit links no lexer and will link no engine; a second host, Atelier's editor, is plausible), returning drawn rows or nil, and nil is today's code block. A TerminalKit ADR records it.
- **The protocol is a cache lookup**, so a block's rows stay a pure function: ask answers from a cache keyed by (block id, width, theme, mode); on a miss it answers nil, lays the diagram out off the main actor, and invalidates the block when it is done. A diagram whose fence is still open is source (0066).
  Past the host's wall-clock guard or the fuel, the block stays source with the reason on its header and the toggle is absent, not dead.
- ask, in `AskTUI` (a few files): scene roles to `Style` through the theme (and so through the follow-the-system colour work), widths from `UnicodeWidth`, the header row as a click target and a key (TerminalKit ADR-0027 and 0031: a fold leaves a placeholder and never moves the reader),
  `ui.diagrams` (`drawing` or `source`), the per-block state kept in the transcript and out of the session file.
- Copy: any selection that touches a drawing yields the Mermaid source. How a drawn row names its source (TerminalKit ADR-0030) is settled by a test first: the first row names the whole fence range, the others name nothing.

## Red first, and the measurements

- **An edit reaches the rows within 4 ms p99**: rows are cached by content hash once 0203 lands (by block id, as the transcript does today, until then), only changed blocks are laid out, and the diagram of an unchanged fence is never laid out again; an edited fence keeps its last drawing until the new layout is ready.
- Rows never exceed the width, at every width from 1 to 200, for the whole corpus; the same diagram at 120 columns draws side by side and at 60 top to bottom.
- The hostile corpus shows no escape byte in any row; a streamed fence is source until it closes; a resize redraws without moving the reader.
- ask's budgets hold: input delay and cold start (`Scripts/measure-budgets.py`, before and after, median and spread, release), and the allocation ceilings of TerminalKit's markdown suite.

## Done when

An assistant message with a mermaid fence draws as a diagram in ask at any width, toggles to source by click and by key, copies source, and falls back to source with a reason for every diagram that cannot be drawn; 0066 is then done.

## Not in scope

Any graphics tier: Kitty and the other raster protocols are dropped (the owner prefers no raster, 2026-11-04; 0066's options B and C), an editor, panning, kinds the engine does not draw (they stay source).

## Progress (2026-11-04)

ask draws a closed `mermaid` fence as a diagram (`Sources/AskTUI/MermaidRows.swift`, called from `MarkdownMessageLayout`), with the theme's styles by role, through the existing row cache; an open fence streams as code and becomes the diagram when it closes, and what the engine cannot read or fit stays code. AskTUI depends on AemiMermaid and ask on the working tree of AemiMarkdown by path until landing. Nine tests; ask's whole suite passes but `BenchmarkDependencyTests`, which needs the revision pin back. Left: a selection that copies the diagram's source, the fold header for a long diagram's source, TerminalKit's `MarkdownFenceRenderer` hook (the promotion), the pins, ask's budgets measured with a diagram on screen, the ADR.
