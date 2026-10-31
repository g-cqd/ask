---
status: done
blocked-by: []
date: 2026-10-31
---

# 0169 — An open thinking block keeps its header row

Owner (2026-10-31): when unfolded, thinking blocks should still use the first line, with the usual 4-character spacer, for the
block's status information.

## Before

Opening a thinking block replaced its `Thinking...` row with the reasoning, and the status (duration, line count, spinner or ✓) was
appended to the reasoning's first row. When that row had no room, the status got a row of its own above. A tool block, by contrast,
keeps its header open and folded.

## Now

Open or folded, the first row is `Thinking...`, then at least `headerGap` (4) cells, then the status at the right edge
(`ScreenComposer.thinkingHeaderRow`, shared by plain and Markdown drawing). The reasoning starts on the row below.

- Open, the header row has no source, so a selection copies the reasoning as written and its rows keep source lines from 0. A click
  on the header still folds the block (`foldBlock`).
- Folded, nothing changed: the header is the block's one row and copies as `Thinking...`.

Tests: `ThinkingFoldingTests` (open reasoning keeps its header row and status, plain and Markdown), written first and red. Updated to
the new look: `BlockModelTests` and `MarkdownEverywhereTests`.
