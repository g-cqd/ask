---
status: done
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

## Result (2026-10-28)

- ESC DEL, ESC BS and `CSI 127;3u` all decode to Backspace with alt, which now deletes the previous word (same boundaries as Ctrl+W).
  Option+Delete (`CSI 3;3~`) deletes the next word; plain forward Delete, ignored until now, deletes one character. Option+Left/Right already
  moved by word.
- No collision with the Esc interrupt (0083): ESC DEL arrives in one read, so the router never reports a lone Escape for it.
- The kit keeps the Delete key's code private; ask names it (57349) until TerminalKit makes it public (TerminalKit roadmap 0020).
- Tests: `OptionBackspaceTests` (decoding through `SequenceRouter` and the edit). Not verified in a real terminal, including terminals whose
  Option key types characters instead of sending ESC.
