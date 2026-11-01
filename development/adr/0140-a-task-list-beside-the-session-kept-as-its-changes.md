---
status: accepted
date: 2026-11-01
---

# 0140 — A task list beside the session, kept as its changes, read through a tool

## Context

Roadmap 0179 (owner, 2026-11-01): a task list inside a session, persisted, not sent to the provider on every turn: the model creates
tasks, marks them done, shows dependencies; a short title and a longer description on demand; reorderable; unique sequential ids; open
tasks shown by default; surviving compaction; never a Markdown file, JSON or protobuf, compressed or encrypted as sessions are
(ADR-0138). The owner's answers: the model reads it through a tool; "blocked by" and "related" links; per session by default, shared
across the workspace by a setting; `/tasks` for the person; open, in progress and done.

## Decision

- **A task**: an id (`t1`, `t2`, … in the order made, never reused), a title (one line), a description (any length, shown on demand), a
  state (`open`, `inProgress`, `done`), the ids it is blocked by, and the ids it is related to. "Blocked" is shown while a blocker is not
  done; it is not a state anyone sets. A link to a task that does not exist, or a blocking cycle, is refused.
- **Kept as its changes**: one record per change (`add`, `edit`, `state`, `move`, `link`, `unlink`, `remove`), appended and flushed as a session's
  are, and the list rebuilt by replaying them. A torn last record is dropped, as in a session. The file is `<session>.tasks` beside the
  session, in the session's format: JSONL when the session is plain, ADR-0138's framed file (its own data key under the same keyring)
  when compressed or encrypted. Compaction never touches it; a fork copies it.
- **`taskScope`**: `session` (default) or `workspace`, for one list at `tasks.ask` beside the project's sessions. A session's own list follows its
  session's format, `/encrypt` included; the workspace's list follows the workspace's `sessionEncryption` and `sessionCompression`,
  written again in them when it is opened, so one session's `/encrypt off` cannot expose a list the others share.
- **The `tasks` tool**: `list` (open and in-progress tasks by default, `all` for done ones too; titles, states, links), `show` (a task's
  description), `add`, `edit`, `start`, `done`, `reopen`, `move` (before or after another), `link` and `unlink` (blocked by, related).
  The model is told the tool exists; the list itself is sent only when the tool is called.
- **`/tasks`**: the picker (roadmap 0116) over the open tasks, a task's description when one is chosen; `/tasks all` with the done ones.
  `/tasks` stops being an old name for `/jobs`.

## Consequences

- The list costs tokens only when read. A model that forgets to read it forgets it: the tool's description says to read it at the
  start of a piece of work.
- `@task` (roadmap 0185) and `#t5` (0186) can point at a task later by its id.
