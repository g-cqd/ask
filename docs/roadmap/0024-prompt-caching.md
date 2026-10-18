---
status: not-started
blocked-by:
date: 2026-10-19
---

# 0024 — Prompt caching

The first live run showed `cache_read_input_tokens: 0` on both turns (1,043 and 1,103 input tokens). ask
re-sends the whole history every turn, so without caching, cost and time-to-first-token grow with the session.

## What lands

- `cache_control` breakpoints on the stable prefix:
  - the end of ask's instructions, in the first user message (ADR-0007 keeps them there, so the breakpoint
    goes there too, not on the system parameter);
  - the most recent stable turn.
- Usage recorded per turn already. A probe shows `cacheRead` rising on the second turn of a live session.
- The interaction with the gate is probed: does a `cache_control` block in the user message still pass?

## Measure

Live, over a 10-turn session: input tokens billed at full rate, and time to first token, before and after.
