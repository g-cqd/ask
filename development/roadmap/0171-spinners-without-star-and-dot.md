---
status: done
blocked-by: []
date: 2026-11-01
---

# 0171 — Spinners without the star and the dot, and a shimmer on running blocks

Wish (2026-11-01): "removing the star effect and single dot from the spinners", and "a shimmer effect to block that are currently
running (especially the text)".

## The plan, as first written (the outcome follows)

- Drop `SpinnerStyle.star` and `.dot` (`Sources/AskTUI/SpinnerStyle.swift`) from the styles and from `random`'s choices. A config
  that still names one gets the default spinner and a notice, as any unknown typed value does (0118).
- The shimmer: a highlight moving along a running block's header text, drawn on the spinner's own tick so it adds no timer.
  Owed first: what it costs per frame against the 4 ms input and 8 ms action budgets, measured on a screen with several jobs
  running, and a setting to turn it off (on or off, typed).

## Done (2026-11-01)

- `SpinnerStyle` has no `dot` or `star`. `SpinnerPreference` still reads both, so a file that names one loads, and they draw the
  default spinner; they are no longer offered (`allCases`), in `/config`, the catalog or the generated example. No notice: the
  file is not wrong, only out of date.
- `ui.shimmer` (on by default): a running block's header has a stretch of `shimmerWidth` (4) columns drawn undimmed (bold on a header
  that is not dim), moving two columns a spinner tick, entering from the left and leaving on the right (`ScreenComposer.shimmering`).
  It rides the spinner's tick and a running block is laid out again every tick already, so it adds no timer and no layout. A header
  with accents of its own is left alone.
- Tests: `ShimmerTests` (4), `SettingTypeErrorTests`, `SettingCatalogTests` (the example); each guard fails a test when removed.
