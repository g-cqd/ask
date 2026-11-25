---
status: accepted
date: 2026-11-17
---

# 0159 — A text, a port or a file is waited for where the command starts

## Context

`bash` and `job` both took `wait_for_output`, `wait_for_port` and `wait_for_file`: a command could be started and waited on in
one call, or started with `yield_seconds` and waited on in a second. Two ways to one end, both paid for in every request, and
the second a round trip longer. The owner (2026-11-17): consolidate, nobody relies on a tool's shape.

What models did with them, in the sessions on this machine (`development/research/tool-calls-in-sessions-2026-11.md`):
`bash` was given a `wait_for` 34 times; `job` twice in 561 calls, both `wait_for_file`. ask's own probes were the main user of
the second way: six of them started a server with `yield_seconds: 1` and then waited for its port with `job`.

## Decision

**`bash` waits for a text, a port or a file; `job` waits for the end.**

- It stays on `bash` because a server started and ready is then one tool call, not two, and the delay between actions is a
  budget here. It is also where models already put it.
- `job`'s `wait` returns when the job ends or its `timeout_seconds` are up, with what the job printed since it was last shown.
  That is enough to follow a job that is already running: wait a few seconds, read.
- A `wait_for` given to `job` is refused, and the refusal says both things to do. It is not ignored: a wait that ignored it
  would sit out its whole time for something it was never watching, and say nothing of it.
- `bash` says what a model could not guess: a `wait_for` that has not happened by `timeout_seconds` stops the command.

## What is lost

Waiting on a job that is already running for a text, a port or a file; and sending a line to a job and waiting for the text
that answers it. Neither appears once in the sessions measured (`input` was never used at all), which is one person's use and
not everybody's: if a need shows, the place to add it is `job`'s `wait`, by a new decision.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| Models wait on `job` for a text, a port or a file | `Scripts/measure-tool-arguments.py bash job` | **Refuted**: 2 of 561, against 34 on `bash` |
| A server started and ready is one call | `probe-agent-run` F and G, rewritten to one `bash` call with `wait_for_port` | **Holds**: `[job-1 port N accepts connections; still running]` in the first result |
| `job` says where a `wait_for` goes, and leaves the job running | `JobActionWaitTests` | **Holds** |
| The tool list shrinks | `Scripts/measure-request-size.py` | **Holds**: 12,035 to 11,880 bytes: `job` 1,262 to 1,030, `bash` 1,794 to 1,871 for the sentence on the timeout |

## Consequences

- `Scripts/probe-wait-gap.py` is removed. It showed, through the binary, that a wait beginning after a megabyte of output was
  dropped does not find a text joined from the two kept ends (ADR-0083). No tool begins a text wait after output any more, so
  the probe could no longer fail. The buffer itself keeps its tests (`OutputBufferTests`, `JobFalseFoundTests`).
- Five probes start their server in one call instead of two.
