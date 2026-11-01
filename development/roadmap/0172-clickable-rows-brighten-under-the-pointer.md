---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0172 — Clickable rows brighten under the pointer

Wish (2026-11-01): a hover effect on what can be clicked besides links: a job row, a thinking block's header, a folded block's first
line.

## Still owed

- Pointer motion without a button pressed needs any-motion tracking (DECSET 1003); today ask asks for button events only. Measure
  what the extra reports cost at idle and while text streams, and whether they reach the 15 MiB idle budget or the input budget.
- Brighten the hovered row (its tint a step toward the foreground, mixed from the page as the tints are, 0108), redraw only that row,
  and clear it when the pointer leaves the window.
- A setting to turn it off.
