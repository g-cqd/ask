---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0088 — Active memory is 21.5 MiB against a 20 MiB budget

ADR-0122: the owner set idle 15 MiB and active 20 MiB, assessed on a loaded machine. `Scripts/measure-budgets.py` samples the
resident size right after a `read` tool call is shown. Loaded, 15 runs, release build: idle 12,384 KiB, **active 22,000 KiB** (p95
22,112; min 21,920) against 20,480. The turn adds about 9.6 MiB.

## Plan

1. Separate what the measurement counts. RSS includes shared system libraries; compare it with the physical footprint (`footprint`
   or `vmmap -summary`) before and after the turn, and say which one the budget means.
2. Attribute the growth: `vmmap` at idle and after the turn, diffed by region (malloc zones, stacks, mapped files). Candidates,
   all unmeasured: the first request's connection pool and TLS state, the JSON codec, the session file, transcript and screen
   buffers, the tool run (a thread and a pipe), a read buffer sized for the largest file.
3. Fix the largest first, with a before and after run each. No budget change without the owner.

## Done when

The loaded median is under 20,480 KiB with the fix named in a diary, or the owner moves the limit.
