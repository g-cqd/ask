---
status: in-progress
blocked-by: []
date: 2026-11-01
---

# 0180 — An ideation board

Wish (2026-11-01): `/idea <text>` saves an idea verbatim, timestamped, without interrupting the turn; `/ideas` lists them with the
picker to edit one; the model can read them when asked or after a task, and mark them acknowledged, fulfilled or dismissed, and see
which are new. Persisted like the task list (0179), which it may build on.

## Still owed

- An idea before the first prompt: there is no session yet, so `/idea` says so. Keeping it until the session starts is open.
- Indexed or semantic search over ideas (wish, 2026-11-01), later.
- `@idea` in the prompt, with 0185's tokens.
- `/idea` keeps the text between its first and last non-space character: the screen trims a command's line before running it.

## Done (2026-11-01)

- Ideas are a list of their own on 0179's store (ADR-0140, section "Ideas on the same store"): `ChangeLog` and `ChangeBoard` are
  generic, the tasks and the ideas two lists of them.
- `/idea TEXT`, at once, during a turn too, never sent to the model. `/ideas`, `/ideas all`; choosing an idea puts `/ideas i3 TEXT` in
  the input with its list closed (`ConversationUpdate.editDraft`: the idea's own words would match its row and the list would take
  Enter), and Enter keeps the edit and opens the list again, with fresh rows.
- The `ideas` tool: list (new ones counted), show, acknowledge, fulfil, dismiss, reopen; it cannot add or edit one.
- Tests: `IdeaListTests`, `IdeaBoardTests` (encrypted, verbatim), `IdeasToolTests`, `EditDraftTests`; 14 mutants, all killed.
  `Scripts/probe-ideas.py` passes 7 checks through the release build in a pty: saved, listed, edited in the input with the list closed,
  the list again with the new words, nothing sent unasked, and the model reading the edit through its tool.
