---
status: done
blocked-by: []
date: 2026-11-01
---

# 0191 — The list tools take batches: lean, typed, all or nothing, safe to repeat

Owner (2026-11-01), after converting the roadmap into the task list took about 260 calls: batch edits and batch actions; then "run a
study of how that should be done … more efficient, less token heavy, maximize type safety, atomic operation, idempotent as well, and
that dont allow too much flexibility … we need limits, constraints, and a cohesive api surface for those 2 tools"; "the tasks and ideas
tool have to be lean, as lean as possible"; "if we could avoid `try!`, that is always better"; and search, which roadmap 0181 owns.

## Done (2026-11-01)

- The study and the decision: ADR-0141.
- One shape for `tasks` and `ideas`: `changes` (1 to 100, made all or none, kept as one record), a `read`, or both. Ids `t3`, `t5-t9`,
  `@1`; lists as one space-separated string. Every change is safe to repeat: what is already so is no change, an add of an existing
  title and detail is that task, a removed task's removal is no change, an id never given is refused.
- Strict input: an unknown field, a field an operation does not take, a malformed id, a value out of its limits refuse the call and
  name the change (`change 3 (state): there is no task t9.`). Limits: 100 changes, 1,000 ids, 2,000 entries, one-line unique titles of
  120 characters, 4,000-character details, 8 tags.
- Reads: views (with `summary`), ids in full, word search over title, tags and detail ranked by field (0181's index will answer the same
  field), limits that say what they left out. Ideas: a line cut at 120 characters, shown whole once by id; marks say which task an idea
  became (`→ t51`).
- Records: tasks gain tags and made/closed times; ideas the tasks they became; old records read unchanged (ideas keep 0180's layout); a
  record a later ask wrote makes a list read-only rather than rewritten without it.
- Lean: the two definitions are 1,351 bytes against 1,333 before, pinned by a test; the schema is built from AskAI's typed `ToolSchema`
  through the stream writer, with no `try!`.
- Found on the way: a typed-throws closure passed where a plain throwing one is expected crashes the Swift 6.4.2 compiler in IR
  generation (`TasksTool.run`); the closures are untyped. `ProviderProxyTests` read once per message and failed when TCP split the
  echo; it now reads until the reply is whole (task t2).
- Tests: `TaskPlannerTests`, `TaskQueryTests`, `ListRefTests`, `ChangeRecordTests`, `TasksToolTests`, `IdeasToolTests`; 44 mutants,
  all killed. `probe-tasks.py` (one call makes the batch and reads it; one `batch` record on disk) and `probe-ideas.py` pass against the
  release build.
