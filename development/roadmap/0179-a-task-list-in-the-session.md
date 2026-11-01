---
status: in-progress
blocked-by: []
date: 2026-11-01
---

# 0179 — A task list in the session, outside the model's context

Wish (2026-11-01): a roadmap and task list inside a session, persisted, not sent to the provider: the model can create tasks, mark
them done, show dependencies; each has a short title and a longer description on demand; tasks can be reordered; ids are unique and
sequential; by default only open tasks are shown. It survives compaction. Persisted in ask's files or in the workspace (for
versioning), by a setting, global or per workspace.

"Still a lot to refine, ask questions."

Owner (2026-11-01): per session or per workspace, never a Markdown file: JSON and/or protobuf, either one compressed or encrypted as
0182 specifies.

Owner (2026-11-01): the model sees the list through a tool it calls, not on every turn. `@` may point at a task later, and `#` too (0185,
0186).

## Questions for the owner before a design

- ~~Does the model see the list on every turn (costs tokens), or only through a tool it calls?~~ Through a tool.
- ~~Dependencies: just "blocked by", or more?~~ "Blocked by" and "related" (owner, 2026-11-01).
- ~~Where by default?~~ Per session; a setting shares one list across the workspace's sessions.
- ~~The person's view?~~ `/tasks`, taken back from `/jobs`, which it opened as an old name.
- ~~States?~~ Open, in progress, done; "blocked" is shown, not set, while a blocker is not done.

## Still owed

- `#t3` in the prompt, through 0186's sigil (owner, 2026-11-01: not `@`).
- A look at `/tasks` in a real terminal: today it answers as a notice, one line a task, and its picker offers `all` and each task.
- Running the probe with an encrypted session: the unit tests cover every format, the probe runs with `ASK_SESSION_ENCRYPTION=off`.

## Done (2026-11-01)

- ADR-0140. `Sources/AskAgentCore/Tasks/`: `TaskList` checks every change (unknown ids, empty titles, a task waiting on itself through
  any number of others, an id given before) and leaves the list as it was when it refuses one; ids are never reused. `TaskLog` keeps
  the changes, one record each, as JSONL or ADR-0138's framed file with a data key of its own, repaired like a session (a torn or
  unreadable record is dropped, the next change writes the file again), capped at 16 MiB, and changed under a lock beside it after
  reading what another process appended, so a workspace's list stays one.
- `taskScope`: `session` (`<session>.tasks`, copied by `/fork`, converted by `/encrypt`) or `workspace` (`tasks.ask`, kept in the
  workspace's own encryption and compression).
- The `tasks` tool: list, show, add, edit, start, done, reopen, remove, move, link, unlink; ids as `t3` or `3`.
- `/tasks`, `/tasks all`, `/tasks t3`, with a picker; `/tasks` no longer opens `/jobs`.
- Tests: `TaskListTests`, `TaskLogTests` (every format, two logs changing one file at once), `TaskBoardTests`, `TasksToolTests`; 18
  mutants, each guard's, all killed. `Scripts/probe-tasks.py` passes against the release build: the tool is offered, the list is never
  sent unasked, the file sits beside the session as change records, and a workspace's second session sees the first one's tasks.
