---
status: in-progress
blocked-by: []
date: 2026-10-20
---

# 0045 — Multi-line prompt editing

Pasted line breaks still become spaces, and the editor has no newline key. Returned queued input can now
contain newlines and the composer draws them, but that is not a complete multi-line editor.

Preserve line breaks in bracketed paste, insert one with Shift+Enter where the terminal reports it and with
a portable alternative, and make up/down and line-boundary editing work across hard and wrapped lines.
Enter submits the whole prompt as one message. Keep the cursor visible within the six-row editor viewport.

## Done when

Editor and layout tests cover newlines, grapheme clusters, wrapping, navigation and submission; a real-PTY probe
sends a multi-line paste and a typed newline, edits them, and checks the exact request and recorded user entry.
Measure the input/render path before and after in release.

## Done (2026-10-20, diary 29)

- A paste keeps its line breaks (CRLF and CR become one `\n`).
- Shift-Enter (where the terminal reports it) and **Ctrl-J** (everywhere) insert a newline; Enter submits the whole
  prompt as one message, and a prompt that is only line breaks is not submitted.
- Up and Down move between lines and remember the wanted column across a short one; Home, End, Ctrl-A, Ctrl-E,
  Ctrl-U and Ctrl-K work on the line (Ctrl-K at a line's end joins the next); Ctrl-W treats a line break as a space.
- The prompt draws one row per line and scrolls within its six rows to keep the cursor visible.
- Returned unsent input (ADR-0037) keeps its lines. Ctrl-U now clears a line, not the prompt, so a restored
  multi-line draft takes one Ctrl-U and Backspace per line to clear.

## Still owed

- **Up and Down across wrapped lines.** They move between hard lines only; a long line that wraps on screen is one
  line to the editor, because the editor does not know the terminal width. Needs the layout's width passed in.
- A key that clears the whole prompt.
- A real terminal check of Shift-Enter: the probe sends it as the CSI-u sequence a keyboard-protocol terminal
  reports, not from a physical key. Ctrl-J has no such dependence.
