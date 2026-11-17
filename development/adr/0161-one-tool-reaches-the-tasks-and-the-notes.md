---
status: accepted
amends: ADR-0141
date: 2026-11-17
---

# 0161 — One tool reaches the tasks and the notes

## Context

`tasks` and `notes` were two tools of one shape (ADR-0141: `changes`, a `read`, or both), over two lists of one store. ADR-0157
had them told in the same words by one builder, and they still cost a model two names, two descriptions and two schemas whose
`read` was the same four fields: 2,656 bytes of every request. The owner (2026-11-17): consolidate.

In the sessions on this machine (`development/research/tool-calls-in-sessions-2026-11.md`): 1,014 `tasks` calls and 459
`notes` calls, three in four of the latter a read.

## Decision

**`notes` is no longer a tool. `tasks` takes `list`: `tasks` unless given, or `notes`.**

- A call is on one list. Everything else of ADR-0141 stands: batches, all or none, safe to repeat, typed, limited.
- On notes a change is a `state` (`acknowledged`, `fulfilled`, `dismissed`) with an optional `task`, as before; it may say
  `op: state`, the word a task's state takes. Any other `op` is refused with why: notes are the person's to write.
- **A call that leaves `list` out and can only mean the notes is on the notes**: an id that starts with `n`, or the view `new`.
  Refusing it would cost a model a call to say what its ids already said. Convenience is a requirement (AGENTS.md).
- The refusals stay each list's own: `done` asked of notes, or `new` of tasks said to be on tasks, name the views there are.

This replaces point 5 of ADR-0157 (one builder for two tools): there is one definition now, and `ListToolSchema` is gone.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| The tool list shrinks | `Scripts/measure-request-size.py` | **Holds**: 11,880 to 11,381 bytes; the definition 2,656 to 2,208 |
| A note's id without `list` reaches the notes | `IdeasToolTests`, four calls; the inference taken out | **Holds**; without it, all four fail |
| The model cannot write a note through the merged tool | `op: add` on `list: notes` | **Holds**: refused, the notes unchanged |
| The real binary reads notes through `tasks` | `probe-ideas`, its call rewritten; `probe-tasks`, `probe-ideas-early`, `probe-agent-run` | **Holds** |

## Consequences

- One schema describes both lists, so it is looser than either: `state` lists six values of which a list takes three, and
  `view` five of which a list takes four. What is wrong for the list is refused by the list, in words, as before.
- **On the screen a call on the notes is headed `tasks`**, where it was `notes`. `/notes` and `/tasks` are unchanged.
- A session recorded with `notes` calls replays as it was: the transcript shows the recorded name.
- **Not known: whether models find the notes as readily behind an argument as behind a name.** The description's first line
  names both; `Scripts/measure-tool-arguments.py tasks --values list` counts it in later sessions.
