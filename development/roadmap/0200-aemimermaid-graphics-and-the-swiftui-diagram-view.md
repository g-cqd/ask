---
status: in-progress
blocked-by: ["0197"]
date: 2026-11-04
---

# 0200 — AemiMermaid: a vector backend and a SwiftUI diagram view, in the system font

The pixel half of the engine (design: `development/research/mermaid-markdown-quicklook-2026-11.md`, sections 6 to 9). Apple platforms only; no dependency beyond the system frameworks and the family.

## What is built

- `AemiMermaidGraphics`: a scene drawn into a `CGContext` as paths and glyph runs, **vector only** (a PDF context or the screen's; no bitmap context anywhere in the target, and none for a preview), text with the system font through CoreText **at its final point size** (never a scaled transform), tabular figures for numbers, the system monospaced font only for the members, columns, ids and backticked labels the research note lists.
  Zoom is a transform of the scene, lossless, with culling by the scene's bounds so a 1000-node diagram costs what is visible; a text-size change re-lays out. Geometry in em of the base font; hairlines snapped to the device pixel; the 10 pt legibility floor (Apple's smallest text style) (a wide diagram re-lays out tighter, then scrolls or zooms, and is never shrunk into small print).
- `AemiMermaidUI`: `MermaidView` draws the scene with `Canvas` (one view, so a 1000-node diagram is not 1000 views). Layout in a task off the main actor, cached by (content hash, metrics key with font, size and scale, width), never by colour. Source is shown until the layout is ready.
  Roles resolve to system semantic colours in the current appearance; a change of appearance redraws without a new layout. Accessibility text (the source, or a generated description) on the view.
- The measurer: CoreText with the system font. Layout with it is tested by properties (the linter of 0197), exact goldens use the table measurer.

## Red first, and the measurements

- The linter passes on the corpus with the real font at several sizes and scales; a diagram is within the container or scrolls; no text under 10 pt; text contrast at least 4.5 to 1 and strokes 3 to 1 in light, dark and Increase Contrast.
- Time from request to first pixel for a 30-node and a 200-node diagram, release, median and spread; the main actor is never blocked by a layout (a test that the layout runs elsewhere, with no wall clock).
- **Vector, checked**: a source test bans `drawingGroup`, `blur`, `shadow`, `compositingGroup` in the target; every kind of the corpus is drawn into a PDF context and the PDF holds zero image objects (the detector shown to fire on a bitmap first, as in the diary's claim 12).
- Allocation ceiling for a redraw (no layout, no allocation per shape).

## Done when

`MermaidView` shows every kind the engine lays out, in light and dark, at 1x and 2x, from the same scene as the terminal; the numbers are in the diary.

## Performance, by measurement (research note, section 13)

Scene culled by bounds (a spatial grid over the display list) so a redraw costs what is visible; paths built once per scene and reused across redraws and zoom levels; glyph runs shaped once per label and kept; strokes grouped by style to cut state changes; one `Canvas` or drawing view per diagram, never a view per node; layout results cached by content hash, bounded by bytes. Kept or reverted by their numbers.

## Not in scope

Editing, animation, a web view, any raster output (the PDF the context gives is the export).

## Progress (2026-11-05)

The vector backend is SVG (`AemiMermaidSVG`, ADR 0006), drawn in the cell grid with the system font; a CoreGraphics drawing exists for thumbnails (flowchart shapes, paths, pie). Open: proportional-font metrics, curved edges, compartments in class boxes, a native SwiftUI diagram view.
