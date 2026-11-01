---
status: not-started
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
- Dependencies: just "blocked by", or more?

## Still owed

- A design record, then a tool for the model and a `/tasks` view with the picker (0116) for the person.
