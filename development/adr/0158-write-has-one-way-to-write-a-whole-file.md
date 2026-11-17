---
status: accepted
date: 2026-11-17
---

# 0158 — `write` has one way to write a whole file

## Context

`write` took the whole file as `content`, or as `new_text` given alone: an alias left from folding `edit` into it. ADR-0157
stopped telling models of the alias and left whether it goes to the owner, who answered (2026-11-17): go ahead, nobody relies
on a tool's shape.

In 1,496 `write` calls in the sessions on this machine, `new_text` came alone once
(`development/research/tool-calls-in-sessions-2026-11.md`).

## Decision

`content` writes the whole file. `old_text` with `new_text` changes a part of it. **`new_text` alone is refused**, and the
refusal names both ways.

Refusing input needs a safety reason (AGENTS.md, Reliability), and this is it: `new_text` alone is at least as likely an edit
that lost its `old_text` as a whole file, and written as the whole file it leaves the file holding only the piece that was
meant to go into it. The refusal costs a model one more call; the other reading costs the person a file.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| Models use the alias | `Scripts/measure-tool-arguments.py write` | **Refuted**: 1 call of 1,496 |
| The refusal leaves the file alone and says what to give | `FileToolsTests`, the file read back after the call | **Holds**; with the alias put back, the test fails twice |

## Consequences

- The schema does not move: no argument was added or removed, so the cached tool list is the same bytes.
- A session recorded with the alias still shows what it wrote: `ToolSummary` reads `new_text` alone as before.
