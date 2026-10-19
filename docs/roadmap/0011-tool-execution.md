---
status: done
blocked-by: 
date: 2026-10-18
---

# 0011 — Tool execution

The protocol every tool implements: a schema in, a structured result out, with error paths that give the
true result rather than an estimate.

## The shape worth matching

pi's `bash` resolves to `{ output, truncated, full_output_path?, exit_code, wall_time_seconds }`, and
the truncation detail is the part that matters: the model's view is capped at 2000 lines / 50 KB, while
`output` itself holds up to 1 MiB, longer output keeps its first and last 512 KiB around an omission
marker, and the full text goes to a temp file named in `full_output_path`.

That is a **budget-preserving** design. A tool that returns an unbounded blob does not fail loudly — it
quietly consumes the context window, and the next several turns degrade for a reason nobody can see.
Head-and-tail with an omission marker keeps the useful part and stays inside the ceiling.

## What lands

- A tool protocol: schema, typed arguments, structured result, typed failure.
- Registry and dispatch, with unknown-tool and bad-argument as first-class errors.
- Output capping with head-and-tail preservation, from the start rather than retrofitted.
- Every tool bounded: attacker input must not exhaust CPU, memory or disk.

## Production subprocesses — decided

[ADR-0011](../adr/0011-official-subprocess-for-tools.md) selects the official
`swiftlang/swift-subprocess` package, introduced with the first real tool rather than speculatively.
Use an injected runner with structured child lifetime and bounded concurrent stdout/stderr draining.
Do not copy Atelier's actor/unstructured-task wrapper wholesale or build another POSIX/Foundation
launcher. Collected-output limits throw: head/tail truncation plus a spool file needs explicit streaming
policy, including a disk cap. Cancellation/descendants and all failure paths need integration fixtures.

## Red TDD

One behaviour per test, named as a sentence. Test the failure paths first — a tool that works on the
happy path and lies on the edge is worse than no tool.

## Done when

A tool takes structured arguments, returns a structured result, caps its own output with the full text
recoverable, and every failure mode is a typed error the model can act on.

## Notes

`0012` depends on this: "call a tool from a script" is not expressible until tools exist.

## Reordered (ADR-0019)

No longer waits for Spettro. Tools sit behind the neutral seam, `(id, name, JSONObject) → (content, isError)`, which OpenAI-completions' `tool_calls` also map onto. The protocol lives in `AskAgentCore` (ADR-0009) and implementations in `AskTools`.

## Progress (2026-10-19)

`read`, `write`, `edit` and `bash` are in `AskTools`, tested, and shipping in `ask`. The contract (`Tool`, and
`ArgumentTool` since ADR-0023) and the uniform output cap are in `AskAgentCore`.

Still owed from "Done when": the **full text of a capped output is not recoverable** (the head-and-tail
cap drops the middle and nothing spools it to a file), and tools that search (`grep`, `find`, `ls`) do not
exist, so the model reads with `bash`.

`bash` runs on swift-subprocess in its own session, with group teardown, a head-and-tail collector and a timeout on an injected clock.

Benchmarks:

| | Before | After |
|---|---|---|
| edit, 1 MiB | 20 ms | 1.23 ms (byte search) |
| read, 1 MiB | 3.97 ms | 0.57 ms |
| cap, 1 MiB | 14 ms | 0.37–0.50 ms |
| bash spawn | — | 2.0 ms |

**Owed:**
- a spool file for full bash output (the 0011 design names it);
- a glob/grep tool, if the model needs more than bash `rg`.

## Done — audit (2026-10-19)

Every line of "Done when" holds: a tool takes structured arguments and returns a structured result; output is capped
with the whole of it recoverable (commands stream to a file that a cut result names, 0031); every failure is a typed
error the model reads, and the sandbox now refuses with the capability and the path (ADR-0035). `read`, `write`,
`edit`, `bash`, `wait`, `job_input` and `job_stop` ship.

What the entry listed as "owed" beyond that, searching tools, is its own entry now: 0043.
