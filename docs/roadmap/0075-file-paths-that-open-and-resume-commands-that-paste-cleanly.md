---
status: not-started
blocked-by: []
date: 2026-10-27
---

# 0075 — File paths that open and resume commands that paste cleanly

File paths shown in UI blocks should be terminal hyperlinks to the actual file,
not merely text that resembles a path. Use an absolute, encoded `file://` target
while displaying a short path: `~/…` inside the home directory and a suitable
workspace-relative path elsewhere. Relative tool paths resolve against the tool's
working directory, not the renderer's. Preserve copy provenance, line references,
folding and wrapping; control characters must not inject terminal sequences.
Plain-text terminals must still show useful paths. Capability handling belongs to
TerminalKit, not a parallel terminal protocol implementation in ask.

## Still owed

- File hyperlinks in tool headers/bodies, diagnostic locations, and other UI blocks
  that identify real files; do not turn arbitrary prose into misleading links.
- A clickable session-file path in the clean-exit banner, with `~/…` display under
  the user's actual home rather than a long absolute home prefix.
- A readable resume command: `cd ~/Developer/g-cqd/ask; ask --resume ~/.local/state/ask/sessions/… --no-sandbox`.
  Do not quote the command or ordinary flags. Quote/escape only path components
  that need protection; never quote a leading `~` so the shell can expand it.
  Preserve exact session selection and all active launch flags.
- Byte-level link-target/label tests, copy tests excluding OSC sequences, wrapped
  and folded block tests, and a terminal-emulator check. Cover spaces, apostrophes,
  non-ASCII paths, outside-home paths and home-prefix lookalikes.
