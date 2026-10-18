---
status: accepted
date: 2026-10-18
---

# 0016 — Every performance-affecting change is benchmarked, and micro-optimisation is expected

## Context

The white paper's performance doctrine said "micro-optimise last" and banned micro-optimisation without
profiler evidence. In practice that ordering read as permission to skip the small work, and the evidence
bar was set at optimisations only. A dependency, a data structure, or an extra system call changed the
program's cost without anyone being required to measure it.

Two recent examples show the gap. ADR-0015's dependencies were measured only because the user asked for
the trade-off. The session file's durability default rested on a Python model of the system calls, not on
the Swift code path that ships.

The user set the direction: changes that can affect performance are all benchmarked, and the project leans
on micro-optimisation as well.

## Decision

1. **Any change that can affect performance carries a benchmark**, not only changes made for speed. Before
   and after, same harness, same release build, median and spread with units, recorded in the diary and
   the commit message.
2. **Micro-optimisation is expected, not a last resort.** The order of attack still says where to look
   first: don't do the work, do less of it, then do it elsewhere or in parallel. It no longer says what to
   skip. An optimisation that moves no number is reverted.
3. **A benchmark runs the shipping code path**, in a release build without testability. A model of that
   path in another language is a probe of the platform, not of `ask`.

This supersedes §2's "micro-optimise last; micro-optimisation without profiler evidence is banned".
Benchmark evidence replaces profiler evidence as the bar. A profiler still finds where to look.

## Consequences

- The package needs a benchmark harness that lands with the code it measures. Aemi already has one, so the
  ecosystem's harness is evaluated before any new one is written.
- Under rule 3, the session file store is not finished: its durability costs come from Python, and it
  has not been compared with AemiIO's file primitives.
- Changes slow down slightly. Accepted: an unknown cost is a cost discovered later, by a user.
