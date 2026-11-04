---
status: in-progress
blocked-by: ["0196"]
date: 2026-11-04
---

# 0197 — AemiMermaid: a linear layered layout for cells and for pixels, and the scene it writes

One layout, two metrics (design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 4). Layout is a pure function of the diagram, the metrics and the width, in integer arithmetic,
so it is cached by content and tested at every width. Every phase has a stated bound, nothing recurses, and the whole is O(K·(n + e + v)) with K a small constant.

## What is built

- `AemiMermaidLayout` and `AemiMermaidScene`. The scene is a flat display list in reused arrays (shapes, paths with end markers, text runs, groups), with **roles, not colours**.
- `Metrics`: *cell* (a unit is a cell; the host passes its width function; padding 1 to 2 columns, none vertically) and *continuous* (fixed-point units; an injected text measurer; geometry in em of the base font, research note section 6).
- The phases and bounds of the table in the research note: cycle removal by the Eades, Lin and Smyth heuristic, longest-path ranking with at most K tightening sweeps (network simplex only if a probe shows it earns its cost), virtual nodes bounded by the sum of spans, K median sweeps, Brandes and Köpf coordinates, orthogonal channel routing with lanes and no per-edge search.
- Kinds: flowchart and state (compound graphs), then sequence (a linear timeline), class and ER (boxes with compartments on the same engine). Pie and Gantt (text bars in the terminal, drawn charts in pixels) are wanted and come after these five (the owner, 2026-11-04), then mindmap, journey, timeline and git graph. A diagram is laid out again, linearly, when its fence changes: not incrementally.
- **Fitting a width** for cells: flip the direction, wrap labels balanced, drop optional padding, else source with the reason; a layout never depends on an earlier width. Fuel counted per phase; running out is a diagnostic, not a hang.

## Red first, and the evidence

- A test lays every corpus diagram out at every width from 1 to 200: no row wider than the width, every label present, same result whatever the previous width.
- A geometric linter on every scene (no overlapping nodes, no edge through a node, every label inside its shape or on its edge), run with the table measurer and, on Apple platforms, with the system font.
- A growth test at 100, 200, 400, 800 and 1600 nodes fits cost against n and fails when it leaves linear by a stated margin; the diary records it beside the survey's tools (diary 2026-11-04-01, claim 2), so the claim is compared, not assumed.
- Differential and visual comparison against the oracles of 0196 on the corpus; the visual review is the owner's.
- An allocation ceiling per diagram once warm; the worst-case memory in bytes asserted from the limits.

## Done when

The five kinds lay out the corpus within budget on cell and continuous metrics, the width sweep and the linter pass in release, the growth test is linear, and the numbers are in the diary with median and spread.

## Performance, by measurement (research note, section 13)

Structure-of-arrays throughout with dense `UInt32` indices; ranks, orders and coordinates in flat arrays; crossing counting with a Fenwick accumulator tree rather than pairwise; counting sorts and bucketed degrees; bit sets for visited and in-cluster flags; integer arithmetic only; per-cell direction masks and a 16-entry glyph table for box drawing in the cell backend (junctions in O(cells), no search);
a text-measurement cache keyed by (label hash, font, size), which the pixel backend needs because CoreText measuring is the expensive step; different diagrams laid out in parallel (one diagram stays sequential: it is linear); fuel checks only at phase and row boundaries so the hot loops carry no counter. Kept or reverted by their numbers, with the scalar-simple version as the oracle.

## Not in scope

A backend (0198, 0200), curved edges, interactive layout, kinds not named above.

## Progress (2026-11-04)

Layout and scene for cells are built: `DiagramScene` (shapes, paths, texts, roles, one arena of text), `MermaidMetrics` (the host's width function), `FlowLayout` (layered, with clusters as frames, width fit by turning and wrapping) and `SequenceLayout`; a geometric linter (no overlapping nodes, no edge through a node, everything inside the scene), a width sweep from 1 to 120, determinism into a reused scene, a growth test at 100 to 800 nodes (it found the drifting chain). 26 to 70 µs per corpus diagram. Left: pixel metrics and the vector backend's needs (0200), network simplex and Brandes and Köpf as experiments, the reference layout oracle, edges to a subgraph's box, state, class and ER, and the allocation ceiling.
