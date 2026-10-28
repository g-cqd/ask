---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0113 — Commands take effect at the next turn, not only when idle

Owner wish (2026-10-28 19:38): a model change should apply at the very next turn instead of waiting for the session to be idle. The same goes
for every command that does not need an idle session (`/tree` does and cannot work this way). Even fork could act on the fly. The owner
asks for an assessment, to be confirmed before any change.

## Still owed (assessment first)

- List every command with what it touches: settings read at the start of a turn (model, thinking, compaction), the session file, the
  transcript, running tools.
- Classify each: applies at the next turn, applies at once, or needs idle, with the reason.
- For fork while running: what a fork of an unfinished turn contains, and whether the running turn continues in the original.
- Bring the table to the owner before implementing.
