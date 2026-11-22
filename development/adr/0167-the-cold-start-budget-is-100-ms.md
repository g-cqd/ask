---
status: accepted
date: 2026-11-22
---

# 0167 — The cold-start budget is 100 ms

Amends ADR-0122's first decision (50 ms); its rule that every budget check runs under load stands.

## Context

On 2026-11-22 `Scripts/install.sh` refused two builds on cold start alone: 69.4 ms and 73.2 ms against 50 (median of 12, under the
harness's load, the machine's load average 7 to 37 beside it). Interleaved runs of the installed build (30e4a425) and the new one gave
67.2, 53.9, 76.2 ms against 51.8, 64.7, 57.7 ms: no regression, and the installed build itself over 50 ms on this machine that day
(diary 2026-11-22-02). The owner then said: "increase the room for the start budget, 100ms is alright".

## Decision

`Budget.coldStartMilliseconds` is 100. The memory, input-delay and action budgets are unchanged.

## Consequences

- 100 ms is about twice what this machine measured under load that day, and about 9 times the idle median of 11.06 ms: the gate
  catches a gross regression, not a slow day. A change's own cost is still shown by an interleaved before-and-after.
- `BudgetTests` pins the number, so moving it again means editing that test and writing down why.
