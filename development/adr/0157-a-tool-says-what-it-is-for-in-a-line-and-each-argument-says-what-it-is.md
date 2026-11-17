---
status: accepted
date: 2026-11-17
---

# 0157 — A tool says what it is for in a line, and each argument says what it is

## Context

The owner (2026-11-17): what models are told about the tools could be better. What they were told, read from a request: of 46
arguments, one said anything of itself; the rest were explained, if at all, in the tool's one paragraph, `read`'s holding twelve
arguments in three sentences. The system prompt named three tools that had been folded into `job`.

Where models went wrong was counted before a word was changed (`development/research/tool-calls-in-sessions-2026-11.md`, 47,074
calls): the failures a description could have prevented were the ones whose rule was written nowhere a model reads when it
writes the value. A `tasks` title over 120 characters (28 refusals), a field or a value its operation does not take (14), a command
shellcheck refuses (269, nine in ten of three kinds), a relative path from the wrong place (90).

Two earlier lines pull the other way and are kept in view: a provider caches the tool list, so its bytes move rarely and all
at once (ADR-0023); and bytes are paid for, in full by a provider without a cache (roadmap 0137, ADR-0141's lean schemas).

## Decision

1. **A tool's description starts with a line saying what it is for**, a sentence of at most 200 characters. It is what a
   `codemode` script's list of tools shows (`CodemodeTool.brief`) and what the on-device model reads when its window is short
   (`AppleToolSchema`'s first sentence). What follows, on lines of its own, is what a model cannot guess: what comes back, what
   is refused and why, which other tool goes on from here.
2. **Every argument says what it is, where it is written**: `ToolProperty.described(_:)`, or a `ToolSchema.Field`'s third
   value, at any depth. A phrase, with the unit, the default ("120 unless given") and the limit a call is refused for. A small
   object may say its fields in one phrase of its own, as `sandbox` does; its text is unchanged (ADR-0115).
3. **What an argument says is not said again in the tool's paragraph.** `read`'s paragraph went from 576 bytes to 244.
4. **An alias is not advertised.** `write` still takes `new_text` alone as the whole file; the model is told one way,
   `content`. Whether the alias goes is a separate decision.
5. **`tasks` and `notes` are told in the same words by one builder** (`ListToolSchema`), being two lists of one store
   (ADR-0141): what a model learns of one holds for the other.
6. `ToolDescriptionsTests` holds 1 and 2 for every tool ask declares, and fails when a tool is declared that it does not read.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| The gate finds an argument nothing says anything of | `job`'s `text` left undescribed | **Holds**: `["job: text"]` |
| A tool the suite does not read fails it | `agent` taken out of the suite's list | **Holds**: the scan of `Sources/AskTools` names it |
| The stale names fail the instructions' test | The old sentence put back | **Holds**: `job_input`, `job_stop` |
| The on-device model still learns where the command goes | `ShellHintTests`, on the schema it is given | **Holds** for the bytes; **not run** against the model |
| Nothing else pinned the old words | The whole release suite | **Holds** after three updates: the pinned schemas, the lists' size ceiling, codemode's `language` |

## Consequences

- **The tool list grows from 8,169 to 12,035 bytes** (`Scripts/measure-request-size.py`, `ask -p hi`, no MCP server): about
  1,300 tokens more at three bytes a token, paid in full on the first request of a cache lifetime and at the cached price
  after. `tasks` and `notes` go from 1,351 to 2,656, past ADR-0141's ceiling, which is raised with its reason beside it.
- Every pinned schema moved, once, together: one cache miss.
- **Not known: whether calls fail less.** The scripted suite replays fixed calls, so only real sessions can say:
  `Scripts/measure-tool-errors.py` counts them again. Until it has, this is a better-argued description, not a measured one.
- Left for the owner, each its own decision: tools that overlap (`write`'s two ways to overwrite, the waits on both `bash` and
  `job`, `tasks` beside `notes`, `narrow_sandbox` beside the per-call `sandbox`, three tools to reach MCP); whether a job ending
  is an error (71 failures that are not the model's); `ToolAliasTable` still mapping other harnesses' names to `edit`, `wait`,
  `job_input` and `job_stop`, which no model is offered.
