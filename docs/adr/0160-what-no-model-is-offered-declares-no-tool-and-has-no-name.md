---
status: accepted
date: 2026-11-17
---

# 0160 — What no model is offered declares no tool and has no name

## Context

`edit` was folded into `write`, and `wait`, `job_input` and `job_stop` into `job`. Three things were left behind, found while
counting what models are told (ADR-0157) and left for the owner, who answered (2026-11-17): go ahead.

- `EditTool`, `WaitTool` and `JobStopTool` still declared a name, a description and a schema that reached no request.
  ADR-0157's gate carried them as exceptions by name.
- `ToolAliasTable` answered other harnesses' names with `edit`, `wait`, `job_input` and `job_stop`: a skill written for
  another harness that allows `Edit` was read as allowing a tool ask does not offer.
- A job ending was thought to be marked as an error: 71 failed `job` calls.

## Decision

1. **A type that is not offered to a model declares no `ToolDefinition`.** What `write` does to part of a file is `FileEdit`,
   an internal function; `job` stops its job itself. `WaitTool` is removed whole: its run (a job, a file or a port, whichever
   came first) had no caller but tests since `job` took over, and waiting has one home now (ADR-0159).
2. **A name from another harness means a tool a model is offered.** `Edit`, `MultiEdit`, `apply_patch` and the like mean
   `write`; `BashOutput`, `KillShell`, `send_command_input`, and ask's own former `wait`, `job_input` and `job_stop`, mean `job`.
3. **A job's wait fails when its command did, and only then**: unchanged, and written down because it was doubted.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| A job ending is marked as an error | The sessions: every result that starts `[job-N ended`, by its mark and its last line | **Refuted**: 378 ended with exit 0 and are not errors; the 62 that are ended with exit 1, as `bash` marks the same command. One stop of 64 is an error, from a job that had ended by itself |
| The table can name a tool nobody is offered and no test notices | `ToolAliasTargetsTests`, with the old rows put back | **Holds** before, **fails** now: `["edit", "job_input", "job_stop", "wait"]` |
| Nothing but tests called the three types | The package built without them | **Holds**: `write` and `job` were the only callers, of `edit` and `job_stop` |
| The gate needs its exceptions | `ToolDescriptionsTests` without `inner` | **Holds** without: every `ToolDefinition(` in `AskTools` is one the suite reads |

## Consequences

- The tests that called `EditTool`, `WaitTool` and `JobStopTool` call `write`, `job` and `bash`: what a model calls is what is
  tested. Three of `WaitTool`'s tests had no equivalent and went with it (a file appearing, with no job; a port, with no job;
  a text across two chunks is kept, on `JobWaiting`).
- `grep`, `find` and `ls` stay in the table though ask has no such tools: files written for other harnesses name them, and the
  table's test lists them as the only names allowed to point at nothing.
- A request is the same bytes: nothing a model is sent changed.
