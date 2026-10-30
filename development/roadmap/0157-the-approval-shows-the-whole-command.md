---
status: done
blocked-by: []
date: 2026-10-30
---

# 0157 — The approval shows the whole command, and leaves no block behind

Owner (2026-10-30): the full command must be readable in the confirmation section, folded but unfoldable, with a blank row right after
it; and confirmations do not appear among the conversation's blocks: only the tool or command block is shown, not a system block.
(This replaces the earlier choice of keeping the answered question as one block.)

## Done (2026-10-30)

- The question no longer repeats the command; the command comes under it, verbatim (`ToolSummary.fullInput`, an MCP call's arguments),
  folded to one row cut with `…` and a dim `(+N lines · Ctrl+O)` when there is more, then a blank row. Ctrl+O, the key that unfolds
  tool output, or a click on it unfolds every line, wrapped, and folds it again. A file's write or edit is named in the question instead.
- An answered question leaves nothing in the conversation, whatever the answer (Enter, Esc, Ctrl+C): the tool's block says whether it
  ran. The tests that pinned the answer block are replaced.
- Tests: `ApprovalCommandTests` (folded row and hint, unfold and fold, short command whole, no block for three answers, click); a mutation
  that ignores Ctrl+O turns it red. Probes rewritten to read "a question is waiting" from the section and what ran from the provider's
  requests; `probe-mcp-screen.py` 12, interactive sections X and S2 pass.
- Found with it: the default write scope (0153) made the verbose sandbox line and `/config`'s sandbox row long (a path per cache per home,
  the workspace's full path), and counted every default run as strict. They now say "the workspace" and "the build caches", and only a
  narrower or different write scope is strict (interactive R, S).

