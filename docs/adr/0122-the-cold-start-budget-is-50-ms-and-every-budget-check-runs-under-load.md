---
status: accepted
date: 2026-10-28
---

# 0122 — The cold-start budget is 50 ms, and every budget check runs under load

## Context

The cold-start budget was 25 ms, set from a median of 11.06 ms measured on an idle machine (roadmap 0004). Since then every
measurement on a working machine has missed it: 27.08 ms median (roadmap 0054), cohorts of 30 to 45 ms (roadmap 0079), a first
run of 55.9 ms under a load average of 60 to 140 (ADR-0038). The cause of the variance was never one thing in ask: the harness
measured the machine's mood. The owner decided on 2026-10-28 that the check must be made with the computer loaded, and that the
time to the first usable frame may be 50 ms.

## Decision

1. `Budget.coldStartMilliseconds` is 50. The idle-memory (24 MiB), input-delay (2 ms) and action (5 ms) budgets are unchanged.
2. `Scripts/measure-budgets.py` starts one busy worker per core for the whole check (`ASK_BUDGET_LOAD=N` sets another number;
   0 turns it off, which the script's own tests use). The report says how many workers ran.
3. A result without load is no longer the number to quote for a budget; it is still the number for a before-and-after of one
   change, taken interleaved.

## Consequences

- 50 ms is about 4x the idle median, so it catches a gross regression and not a few milliseconds. Per-change numbers carry the
  fine detail, as for memory (ADR-0038).
- Load from busy loops is crude: it takes CPU, not memory or disk. It is the repeatable part of "a loaded computer".
- Roadmap 0054's open question (the efficiency-core share) is settled for the gate by this, and stays open as a diagnosis.

## Probes

Not run for this ADR: the harness change is exercised by `Scripts/test-measurements.py`, and the loaded numbers are recorded in
the diary entry of the same day.
