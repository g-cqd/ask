---
status: not-started
blocked-by: ["0065"]
date: 2026-10-25
---

# 0066 — Mermaid diagrams in the transcript: drawn in the terminal where they can be, shown as source where they cannot

A fenced block whose info string is `mermaid` is a diagram. Today it would be drawn as code (roadmap 0065, phase 3). The owner wants it drawn
as a diagram, at whatever width the terminal has, and redrawn when the terminal is resized. Nothing below is built; every claim marked
*unprobed* is an open question until phase 0 has run it.

## What is known (probed 2026-10-25)

- No Mermaid renderer is installed here: `mmdc`, `mermaid-ascii` and `mermaid` are not on the path. `node`, `deno` and `bun` are.
- Mermaid's own renderer is documented to need a browser's DOM and layout (the reference CLI, `mmdc`, drives headless Chromium). *Unprobed here.* ask links no JavaScript engine
  and starts in a budgeted time, so running Mermaid itself in ask's process is out; as an optional external helper it is a question (below).

## Options, to be probed rather than chosen

| Option | Cost | Risk |
|---|---|---|
| **A. Native Swift, a subset, as text** (box-drawing): a parser for the diagram kinds LLMs write most, a layout, and a cell-grid renderer | The most work; fully in budget; resizes for free, since it is the same cell pipeline | Never matches Mermaid's layout; only a subset |
| **B. Native layout, rasterised, drawn by the terminal's graphics protocol** (Kitty, iTerm2, Sixel) | A rasteriser and a protocol per terminal; ask's graphics work is owed (0051) | Not every terminal; a resize means a new raster; selection and copy of an image |
| **C. An external helper** (`mmdc`, or a user-configured command) | Small; exact Mermaid output | Needs a browser and Node on the user's machine; seconds of latency; **executes a tool on model-controlled text**, so it needs the sandbox and a trust decision |
| **D. Source only**, a labelled, highlighted code block | Nothing | No diagram |

Proposed order, each independently shippable: **D** (already the result of 0065), then **A** for the kinds the corpus shows, with **D** as the
fallback for everything else; **B** and **C** are later, and only if A's coverage turns out to matter.

## Phases

0. **Evidence, in the diary.**
   - *Corpus:* how often assistant text and tool results contain a `mermaid` fence, and which diagram kinds (`flowchart`/`graph`,
     `sequenceDiagram`, `classDiagram`, `stateDiagram`, `erDiagram`, `gantt`, `pie`, `journey`, `gitGraph`, `mindmap`), by count. The subset is
     cut by this table.
   - *Prior art, run, not read:* the terminal Mermaid renderers that exist (for example `mermaid-ascii`, `mmdc` with a text exporter), against
     edge cases: wide characters, long labels, cycles, a hundred nodes, a deeply nested subgraph, an unterminated diagram, hostile labels with
     escape sequences. Same method as the glow probe in the diary of 2026-10-25.
   - *Layout:* which algorithm: layered (Sugiyama) for flowcharts, with cycle breaking, rank assignment, crossing reduction and orthogonal edge
     routing on a character grid; timelines for sequence diagrams. Measure it on the corpus: milliseconds per diagram, allocations, the
     worst case at the limits.
1. **Parse a subset**, flowcharts and sequence diagrams first unless phase 0 says otherwise. Bounded: nodes, edges, label length and nesting
   have limits; an input over a limit, or any syntax outside the subset, is shown as source with a one-line reason (`diagram too large: 412
   nodes, limit 200`), never dropped and never a crash. No recursion; an explicit stack.
2. **Lay out for a width.** A pure function of the parsed diagram and the columns, like every other formatting (0065, "Adapts to the
   terminal's size"): the same diagram at 120 columns is drawn side by side, at 60 it is drawn top to bottom, wraps its labels, and below the
   smallest width it can be drawn in it falls back to source. A test lays one diagram out at every width from 1 to 200: no row wider than the
   width, every label present, and a layout that does not depend on earlier widths.
3. **Draw into cells**, with the same `Style` runs as the rest of the transcript and the terminal palette, edges and boxes in box-drawing
   characters whose width `UnicodeWidth` agrees on (ambiguous-width characters are measured first, TerminalKit roadmap 0013), with an ASCII
   mode. Labels are untrusted text and go through the sanitizer of 0065.
4. **Copy and fold.** A selection over a diagram copies the Mermaid source (the owner's rule for Markdown, 0065). A long diagram folds like a
   long code block (`ui.codeFoldLines`), and the header names the kind and the size.
5. **More kinds**, in the order of the corpus.

## Safety and budgets

- A diagram is attacker input: a model, a fetched page or a file can write one. The limits above are the defence, and a fuzz target feeds the
  parser arbitrary bytes.
- Layout runs off the main actor, and a diagram that takes longer than a stated budget (decided by the measurement in phase 0) is shown as
  source and finished later; the input-delay budget of `AskCore.Budget` holds.
- The switch is `ui.markdown`'s neighbour, `ui.diagrams`, default on; off draws the code block.

## Not in scope

An editor for diagrams, exporting to image files, interactive panning, and Mermaid's theming and click callbacks (a `click` directive is ignored,
never run).
