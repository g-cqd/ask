---
status: not-started
blocked-by: ["0013", "0003"]
date: 2026-10-18
---

# 0015 — A compact UI drawn in pixels where the terminal allows it

The point of the pixel work: **as much room as possible for content**. Every structural element that
costs a cell should cost pixels instead.

## What pixels buy, concretely

| Element | Character cost | Pixel cost |
|---|---|---|
| Horizontal rule between panes | a whole row of `─` | `.line`, 1px, no row |
| Vertical gutter rule | a column of `│` | `.line`, 1px, no column |
| Pane or selection background | no cells — background colour | `.fill`, no cells |
| Scrollbar thumb at 40% | 1 character (`█`, `▓`, `░`…) | `.bar` at an exact pixel offset, **no column** |
| Header band | a row of spaces/backgrounds | `.fill` across the row |

That last column is the whole argument. `.bar` is the one that matters most: a proportional scrollbar
is *four characters* in any cell-based UI, and one placement in a pixel one.

## The hard constraint, stated up front

Pixel chrome is **kitty-graphics-protocol only** — kitty, ghostty, wezterm, konsole. Terminal.app is not
in the list.

So a pixel-first UI needs a character-mode fallback, and **it must look intentional rather than broken**.
A layout that collapses on an unsupported terminal reads as a defect to anyone using Terminal.app, which
ships on macOS. This doubles the UI surface.

Decide that before designing anything: either the compact layout is the baseline and pixels only refine
it, or the layouts diverge and both need designing.

## Ordering

After `0013` (the chrome lives in the renderer) and after `0003` (capability detection decides whether
chrome can be used at all) and after `0014`'s numbers.

## Done when

The same layout renders on a graphics terminal with chrome and without it on Terminal.app, neither looks
broken, and the content area is measurably larger than the character-only layout — measured, not
asserted.