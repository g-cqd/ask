---
status: done
blocked-by:
date: 2026-10-18
closed-by: ADR-0010
---

# 0005 — Correct the cross-repo blocker recorded against roadmap 0001

`0001` is `in-progress`, and `0003` is `blocked-by: ["0001"]`. Probed: `grep` for `Atelier` and
`KittyCode` across `Package.swift` and `Sources/` returns nothing. **`ask` does not depend on Atelier.**

What `0001`'s own "Still required" says is *"switch Atelier to the shared implementation"*. That is
Atelier's work, tracked in `TerminalKit/development/roadmap/0003-atelier-consumes-terminalkit.md`, and it is
step 4 of that entry's own six remaining steps.

## What is wrong

A blocking relationship was recorded between two repositories that do not depend on each other. The
consequence is concrete: `0003` — active capability probing, which gates the input-delay budget — is
gated behind another team's migration with no path from `ask` to unblocking it.

## Why it is not already fixed

`0001` is `in-progress` and reads as genuinely open, so correcting it reverses a recorded status. Per
the documentation law that is a **new ADR that supersedes**, not an edit to the entry.

## Options

1. **Rescope `0001`** to what remains in `ask`, mark it done, and point at TerminalKit `0003` for the
   consumer switch. `0003` unblocks immediately.
2. **Repoint `0003`'s `blocked-by`** at nothing, leaving `0001` alone. Smaller change, leaves the
   misleading entry in place for the next reader.
3. **Leave it.** Costs: capability probing — and through it the input-delay budget — stays gated on
   Atelier's migration for no reason.

## Done when

`0001`'s status reflects reality and names where its remaining work actually lives, `0003` is
unblocked or re-pointed, and an ADR records the correction and its probe.

## Done

ADR-0010. `grep` found no reference to Atelier anywhere in `ask` outside comments; `0001` is closed,
`0003`'s blocker was re-pointed at `0014`, and the ADR records the probe plus the pattern this is the
third instance of.