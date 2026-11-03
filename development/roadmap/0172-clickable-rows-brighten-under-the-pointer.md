---
status: done
blocked-by: []
date: 2026-11-01
---

# 0172 — Clickable rows brighten under the pointer

Wish (2026-11-01): a hover effect on what can be clicked besides links: a job row, a thinking block's header, a folded block's first
line.

## Measured first (2026-11-01, debug build, a 1,200-item session on a 120 by 40 screen)

| | |
|---|---:|
| one motion report, the hovered row unchanged | 1.8 µs |
| a whole frame drawn | 0.16 ms |

Against the 4 ms input budget, at the 60 to 120 reports a second a trackpad sends, even a redraw for every report would be about 2 % of
a core; only a change of what is hovered redraws, and the frame's row diff writes the row or two that changed.

## Done (2026-11-01)

- TerminalKit `c58f952`: `TerminalModes.mouseMotion` asks for motion reports with no button held (`?1003`), only with the mouse, off
  by default; the reset ladder already clears it on the way out, so no line of its own is needed.
- `ui.hover` (on by default, needs `ui.mouse`): the terminal reports motion, and what a click acts on brightens under the pointer, no
  longer dim and bold: a foldable block's header (from any row the block owns, as a click toggles it), a job's row in the list below
  the input. Kept as the thing hovered, not a screen row, so a scroll never lights another row. A motion report never reaches the
  pointer recognizer, so it selects and drags nothing.
- Tests: TerminalKit's `TerminalSessionMotionTests`; ask's `HoverTests`; mutants all killed, and two redundant guards removed (the
  explicit 1003 off, which the ladder does; no button held, which a motion report always is).
- Picker rows and the sidebar's rows (2026-11-02): `Hover.picker(Int)` and `Sidebar` brightening for `.job(id)`, verified in `HoverTests`.
- Not done: a look in a real terminal.
