---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0171 — Spinners without the star and the dot, and a shimmer on running blocks

Wish (2026-11-01): "removing the star effect and single dot from the spinners", and "a shimmer effect to block that are currently
running (especially the text)".

## Still owed

- Drop `SpinnerStyle.star` and `.dot` (`Sources/AskTUI/SpinnerStyle.swift`) from the styles and from `random`'s choices. A config
  that still names one gets the default spinner and a notice, as any unknown typed value does (0118).
- The shimmer: a highlight moving along a running block's header text, drawn on the spinner's own tick so it adds no timer.
  Owed first: what it costs per frame against the 4 ms input and 8 ms action budgets, measured on a screen with several jobs
  running, and a setting to turn it off (on or off, typed).
