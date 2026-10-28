---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0108 — Colours follow the system appearance

Owner wish (2026-10-28 19:10), marked highly critical: colour support should read the current macOS appearance, change when it changes,
and match it by default, so colours and contrast work with the terminal's configuration (for example a terminal in light mode). Verify with
screenshots and printed mocked sessions that show the various blocks and how they look.

## Still owed

- Detect the appearance through a system API, not a subprocess (white paper rule): AppKit's effective appearance or the
  `AppleInterfaceStyle` default, and follow its change notification while ask runs.
- Cross-check against the terminal itself: OSC 11 (background colour query), because a terminal's theme can differ from the system's.
  Decide which wins when they disagree, and record it here.
- A light and a dark palette for every styled element: tints, the status colours, dim text, the purple of 0106 and the yellow of 0107.
- Check contrast for both palettes, not by eye only.
- Evidence: mocked sessions rendered in both appearances, captured as screenshots from a real terminal, plus PTY snapshots.

## Open questions

- Should a `ui` key override the detection (`"appearance": "auto" | "light" | "dark"`)?
- Over SSH or in tmux, where the system appearance belongs to another machine, is OSC 11 the only source?
