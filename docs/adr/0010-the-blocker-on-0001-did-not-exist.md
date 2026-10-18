---
status: accepted
date: 2026-10-18
supersedes: roadmap 0001's blocking relationship
---

# 0010 — The blocker recorded against roadmap 0001 did not exist

## Context

`ask`'s roadmap `0001` was `in-progress`, and `0003` carried `blocked-by: ["0001"]`. The intent was to
stop a terminal entry point being started while the terminal stack was still mid-extraction.

A blocking relationship recorded in the wrong direction costs more than a missing one, because it
looks like progress being made and it is not.

## The probe

`grep -rn "Atelier" Package.swift Sources/` in `ask`.

**REFUTED.** Zero references outside comments. `ask`'s manifest depends on TerminalKit and Aemi, and on
nothing else. There is no path — not a target dependency, not a test dependency, not a package
dependency — from `ask` to `Atelier`.

What `0001`'s own "Still required" section asks for is *"switch Atelier to the shared implementation,
verify all affected consumers, and remove duplicate implementation bodies"* — and it names
`TerminalKit/docs/roadmap/0003-atelier-consumes-terminalkit.md` as the owner. So `0001`'s remaining work
is Atelier's, recorded in TerminalKit, and it was never `ask`'s to do.

Meanwhile `0003` — active capability probing, which gates the **input-delay budget** — sat behind it.

## Decision

`0001` is closed in `ask`. The work it describes belongs to TerminalKit's `0003`, where it was already
tracked, and this entry records the correction so the two repositories do not each believe the other
owns it.

`0003` is unblocked and, since `0014` landed, is in fact unblocked *by* `0014` — which is where its
real dependency was.

## Why the entry existed at all, recorded honestly

The extraction itself is done. TerminalKit holds all six modules, the owning suites run there (368
tests across seven targets), and `ask` links the shared stack. What remained was consumer switchover,
which is a different repository's task and always was.

## Consequences

- `0003` loses a blocker that never applied and gains the one that does.
- Nothing about the code changes. This is a correction to a record, which is why it is an ADR and not
  a commit against the manifest.
- `ECOSYSTEM.md` tracks cross-repository decisions; it should point here rather than implying `ask`
  waits on Atelier.

## The pattern, because it has now happened three times

1. The terminal seam assumed three modules; the import closure found six.
2. `AGENTS.md`'s primitive-replacement table was read as "unavailable" when the macOS 26 floor permits
   every one of them.
3. This: a blocking relationship between repositories that do not depend on each other.

In all three the belief was reasonable and the check was cheap. Two of the three were caught by a
`grep`, and the third by reading a guidance table against the floor rather than against reality. The
recurring shape is **a recorded fact that is never re-checked against the thing it describes** — so the
guard is to probe recorded facts, not just new claims.