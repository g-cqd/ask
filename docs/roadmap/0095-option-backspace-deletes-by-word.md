---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0095 — Option+Backspace deletes a word in the input

Owner wish (2026-10-28 16:25). Ctrl+W already deletes a word backward (`PromptEditor.swift`, `0x17`). Terminals send Option+Backspace as
ESC then DEL (`1b 7f`), or `1b 08` with some settings, and Kitty-protocol terminals send an explicit alt modifier.

## Plan

- Probe how `SequenceRouter` in TerminalKit reports `1b 7f` today (likely an Escape key followed by Backspace, which in ask also
  starts the Esc-interrupt arm of 0083: check the two do not collide).
- Map it to the editor's word-deletion with the same boundaries as Ctrl+W; add Option+Delete (forward) and Option+Left/Right if they are
  missing, because they belong to the same family and the person will expect them.
- Tests in TerminalKit (key decoding) and `PromptEditor` (the deletion). Same area as 0082; do them together.
