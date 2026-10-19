---
status: not-started
blocked-by: ["0014"]
date: 2026-10-18
---

# 0012 — The codemode host

Deliberately last in the agent build. It is the most novel piece, the most expensive to get wrong, and it
needs providers and tools to exist before its central affordance is even expressible.

## What it is

Rather than emitting many tool calls, the model writes one script that composes them: filter a list, fan
out with `Promise.allSettled`, aggregate, and make one round trip instead of twenty. Cheap fan-out in one
call is where a large part of the action-to-action budget is won or lost.

## Why it is last

- It requires `0011` — a script calls tools, so tools must exist.
- Its limits are the design: a memory cap, a hard deadline, an output cap, and a cap on concurrent
  workers. Those numbers are *the* design, and getting them wrong is a resource-exhaustion bug.
- It needs `0014`'s answer before it can decide how a script renders results, because whether output is
  text, an image or a pixel-placed region depends on what the terminal can do.

## Shape to study before designing

pi's host: raw JavaScript as the body of an async function, so top-level `await` and `return` work; no
Node, no filesystem, no network, no timers — the outside world is reached only through `tools` and
`models`. A script's result is ordered text and image items with a wall time; calls made before a failure
are **not** undone; running calls are cancelled when the script ends.

Those semantics are worth copying deliberately, because each one is a decision a user can feel.

## Red TDD

The limits are the tests: exceeding memory, exceeding the deadline, exceeding output, exceeding the
worker count. Each must **fail** rather than silently truncate, with the reason reported.

## Done when

One script can compose many tool calls, every limit is enforced and reported, and a cancelled script
leaves no work running.