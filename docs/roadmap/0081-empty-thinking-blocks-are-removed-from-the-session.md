---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0081 — Empty thinking blocks are removed from the session

Owner request, from `ask-wishes.md`: remove empty thinking blocks from the session blocks.

## Still owed

- Find where an empty or whitespace-only thinking block still reaches the screen. `Transcript.swift` already
  drops thinking whose kept text is empty on one path (around line 130), so first reproduce it: a streamed
  thinking block that ends empty, a block holding only whitespace or a redacted marker, and a resumed session.
- Remove them from the displayed blocks only. The persisted session file and what is sent back to the provider
  do not change; check that a provider which needs the empty thinking block (signature or replay rules) still
  gets it.
- Tests for each case above, and a check that a non-empty thinking block is unaffected.
