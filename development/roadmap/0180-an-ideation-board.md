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
- `#i2` in the prompt, through 0186's sigil (owner, 2026-11-01: not `@`).
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

## An idea before the first prompt (2026-11-02)

The owner's choice: `/idea` typed before any session is kept, and saved when the session starts. `ChangeBoard.hold(_:)` keeps the change
(with the time it was typed) while no list is attached, and `applyHeld()` makes the held changes in order once one is; the turn calls it
right after making its session, and says which ideas it saved ("Saved the idea typed before the session started: i1."). A list that
failed to open still says why, rather than holding. Tests: `IdeaBoardTests` (2 new); `Scripts/probe-ideas-early.py` through the release
binary (3 checks; the build before fails the first).

## Renamed to `/notes`, `:subcommands`, `notes` tool and `n1` IDs (2026-11-02)

The owner's design:
- `/idea` and `/ideas` are replaced by `/notes`, with `:subcommands`:
  - `/notes`: opens the picker to select a note (or `all`) and shows it in the transcript.
  - `/notes TEXT` or `/notes:add TEXT`: keeps `TEXT` as a new note.
  - `/notes:all` (or `/notes all`): lists every note in the transcript, fulfilled and dismissed included.
  - `/notes:show n8`: shows note `n8` in the transcript.
  - `/notes:edit n8` (and `/notes:edit n8 TEXT`): puts `/notes:edit n8 TEXT` in the input to edit with the picker closed, and Enter saves
    the edit and reopens `/notes `.
  - `/notes:delete n8`: removes note `n8` (`IdeaChange.remove(id:)`).
  - `/notes:search TEXT`: searches through all notes (`IdeaList.searching(_:in:)`).
- The model's tool is `notes` and item IDs are `n1`, `n2`, … (`#n1` in prompt references; `#i1` still accepted for existing references).
- `SlashInput` and `SlashCommand` accept `:subcommands` on commands.
- Verified: unit tests (`IdeaListTests`, `IdeasToolTests`, `ListReferencesTests`, `EditDraftTests`, `SlashInputTests`) and PTY probes
  (`Scripts/probe-ideas.py`, 8 checks; `Scripts/probe-ideas-early.py`, 3 checks).
