---
status: done
blocked-by: []
date: 2026-10-20
---

# 0049 — Multi-line prompt editing

Preserve line breaks in bracketed paste, insert one with Shift+Enter where the terminal reports it and with
a portable alternative, and make up/down and line-boundary editing work across hard and wrapped lines.
Enter submits the whole prompt as one message. Keep the cursor visible within the bounded editor viewport:
six requested display rows by default, capped at a third of the terminal (ADR-0046/0059).

## Done when

Editor and layout tests cover newlines, grapheme clusters, wrapping, navigation and submission; a real-PTY probe
sends a multi-line paste and a typed newline, edits them, and checks the exact request and recorded user entry.
Measure the input/render path before and after in release.

## Done (2026-10-20, diary 32)

- A paste keeps its line breaks (CRLF and CR become one `\n`).
- Shift-Enter (where the terminal reports it) and **Ctrl-J** (everywhere) insert a newline; Enter submits the whole
  prompt as one message, and a prompt that is only line breaks is not submitted.
- Up and Down move between lines and remember the wanted column across a short one; Home, End, Ctrl-A, Ctrl-E,
  Ctrl-U and Ctrl-K work on the line (Ctrl-K at a line's end joins the next); Ctrl-W treats a line break as a space.
- The prompt draws one row per line and scrolls within its six rows to keep the cursor visible.
- Returned unsent input (ADR-0040) keeps its lines. Ctrl-U clears a line, not the prompt.

## Implemented (2026-10-22, diary 6)

- Up/Down follow TerminalKit's wrapped display rows, retaining the wanted cell column and snapping before wide graphemes. The driver
  passes width and updates it after resize. Home/End and the line-editing controls remain hard-line operations.
- Ctrl-X clears the entire draft without submitting it.
- `ui.promptRows` tunes the requested height. The shared layout/viewport clips display rows, never source text; the status row names a
  clipped range, even behind a long model label on narrow terminals. Empty/tiny buffers have explicit boundary tests.
- The input PTY probe checks ASCII, wide text, tabs, resize, the two-row setting, exact API text and recorded session text. The earlier
  multiline and queue-recovery probes still pass. Release cold-layout, cached-frame, navigation and shipping-budget costs are recorded.

## Still owed

- A real terminal check of Shift-Enter: the probe sends it as the CSI-u sequence a keyboard-protocol terminal
  reports, not from a physical key. Ctrl-J has no such dependence.

## Closed (2026-10-31)

Everything in "Done when" is built and probed. The one item left, Shift-Enter from a physical key, is a check in a real terminal, not
work; it moved to the real-terminal list in `research/priorities-2026-10-31.md`.
