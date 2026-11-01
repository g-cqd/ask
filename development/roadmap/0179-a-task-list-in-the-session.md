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

## Questions for the owner before a design

- One list per session, per workspace, or both?
- The workspace format: a Markdown file people edit by hand, or a JSON file ask owns?
- Does the model see the list on every turn (costs tokens), or only through a tool it calls?
- Dependencies: just "blocked by", or more?

## Still owed

- A design record, then a tool for the model and a `/tasks` view with the picker (0116) for the person.
