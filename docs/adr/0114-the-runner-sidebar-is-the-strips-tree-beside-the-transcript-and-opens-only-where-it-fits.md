---
status: accepted
date: 2026-10-26
---

# 0114 — The runner sidebar is the strip's tree beside the transcript, and opens only where it fits

## Context

Roadmap 0062 step 4: the same runner tree in a sidebar, character layout first, with the same keys and clicks. The roadmap said "open by default in the workbench layout".
**No layout setting exists in the code** (`standard` and `workbench` live in the UI prototype), so there is nothing to be the default of.

## Decision

- **The panel** (`Sidebar`) is a column at the right of the **transcript rows only**; the status line, the picker, the input and the strip keep the whole width. A dim `│`
  divider, one column of air, then the rows: `RunnerStrip`'s own rows (name, detail, state, indentation, `N hidden`, the selection in bold), so the strip and the panel
  cannot disagree. With no runners it says `no runners`. It is **drawn at the top** while the transcript stays bottom-aligned.
- **Width:** a quarter of the screen, at least 20 and at most 32 columns, and **only on a screen of 70 columns or more**; below that nothing is taken from the transcript. Both
  numbers are mine (the roadmap left the width open) and are constants in `Sidebar`.
- **The transcript is wrapped to what is left** (`FrameGeometry.transcriptColumns`); selection, folds and clicks in it use that width, and the divider and the panel are
  not content. Everything that used the screen width for the transcript now uses it, and everything else still uses `columns`.
- **Keys and clicks are the strip's.** Down from the end of a draft enters whichever of the two is shown, Enter or a click focuses a runner (ADR-0110), and the strip and the
  panel share one selection and one set of collapsed parents. A click on the divider or on a blank row does nothing.
- **Toggle:** Ctrl+\ and `/sidebar` (so the mouse and the chord are both optional). The roadmap named no key; Ctrl+B, which I first proposed, is the editor's cursor-left. `/sidebar`
  on a screen under 70 columns says so rather than seeming to do nothing.
- **Default:** `ui.sidebar` is `"open"` or `"closed"`, **default closed**, because the layout it should default to does not exist. When layouts are built, the workbench
  layout can default it open without changing anything here.
- **Not in the panel:** a "context" section. What it lists (model, files, tokens) is still undecided and nothing here pretends otherwise.
- **The row cache** (`ScreenComposer.Shown`) now includes what a row carries at its right edge, so toggling or resizing repaints exactly the rows that change.

## Not built

Pixel strokes for the divider (roadmap 0014/0003), a drag-resizable width, the context section, and anything for agents until 0063.

## Consequences

A wide terminal can keep the runner tree in view all the time at the cost of a quarter of the transcript's width. The panel costs a measured 2 µs per keystroke frame even when closed
(diary 2026-10-26 (3)); when open, about 25 µs more.
