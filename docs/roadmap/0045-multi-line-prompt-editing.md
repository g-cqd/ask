---
status: not-started
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
