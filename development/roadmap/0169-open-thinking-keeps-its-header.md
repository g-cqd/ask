---
status: done
blocked-by: []
date: 2026-10-31
---

# 0169 — An open thinking block's first line carries its status

Owner (2026-10-31): when unfolded, thinking blocks should still use the first line, with the usual 4-character spacer, for the
block's status information. Clarified: the `Thinking...` text is replaced by the first line of the reasoning itself. A first
attempt (`31955d1`) kept a separate `Thinking...` header row above the open reasoning. That was a misreading, and it is reverted.

## Before

Open, the reasoning's first row carried the status (duration, line count, spinner or ✓) at its right edge only when the row had room.
Drawn as Markdown, the reasoning wraps at the full width, so a long first line pushed the status onto a row of its own above it.
Without Markdown, the first line was already cut short of the status, as a tool's header is, with the rest wrapped below.

## Now

Drawn as Markdown, the reasoning's first top-level block wraps at the width less the status and `headerGap` (4).
`ScreenComposer.markdownLines(firstBlockWidth:)` does this, and the first row then always has room for the status. The rest of the
first block stays clear of the status column, and later blocks use the full width. A screen too narrow to leave 20 columns beside
the status keeps the old behaviour: the status gets a row of its own. Folded, the block still reads `Thinking...`.

Test: `ThinkingFoldingTests`, "open reasoning keeps its status on its first line, however long", plain and Markdown. Written first;
the Markdown case was red.
