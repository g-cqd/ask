---
status: done
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

## Result (2026-10-28)

A thinking block whose text is empty or only white space (as a provider that hides its reasoning streams it) shows `Thinking...` with its
spinner while it is live, then leaves the screen when it ends: when anything follows it, or when the run ends
(`Transcript.finishThinking`). Before, it stayed as a header that opened on nothing; `" \t "` even opened onto blank rows, because only line
feeds were trimmed. One predicate, `Transcript.saysSomething`, now decides foldability, the shown text and the removal.

A resumed session reaches the screen through the same updates (`AgentConversation.history` maps replayed events with `update(for:)`), so it
takes the tested path. The change is in `AskTUI` only: the session file and the provider replay keep the block, with its signature.

Tests (`ThinkingFoldingTests`): empty, line feeds and mixed white space, each followed by an answer; at the end of a run; before a tool, whose
index and output stay right; non-empty reasoning with blank edges kept as it is. The new tests fail without the change.
