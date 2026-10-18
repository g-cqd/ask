---
status: not-started
blocked-by:
date: 2026-10-18
decision: ADR-0009
---

# 0016 — Restructure the targets to the graph ADR-0009 fixes

`ask` is three targets against a manifest naming six, and two of those six describe three jobs each.
This lands the graph the ADR fixes, one target at a time, each independently buildable and green.

## The graph

```
AskCore        budgets, session identity, documentation layout     (no internal deps)
AskAI          providers, streaming, protocol adapters, catalog,
               auth, request construction           deps: AskCore    [LEAF within the package]
AskAgentCore   the loop, turn management, session tree,
               context construction                  deps: AskAI
AskTools       read, write, edit, bash               deps: AskAgentCore
AskTUI         screen model, widgets, input routing  deps: TerminalKit only
AskCodeMode    the codemode host                     deps: AskAI, AskTools
ask            composition root — the only target that sees everything
```

`ask`'s manifest header currently describes `AskTerminal`, which ADR-0009 removes: its two stated jobs —
capability negotiation and the reset ladder — are TerminalKit's and `0003`'s, not a layer in `ask`.

## Slicing

One target per commit, each leaving the package green, because a restructure that fails halfway should
cost one commit to undo:

1. `AskAI` — smallest leaf, no behaviour change to anything existing. Proves the graph works before
   anything depends on it.
2. `AskAgentCore` — the loop, session tree and context construction. Carries `0008` and `0009` into it.
3. `AskTools` — the tool protocol's implementations, with `0011`.
4. `AskCodeMode` — last, with `0012`.
5. The manifest header comment, rewritten to describe targets that exist.

`AskCore` and `AskTUI` keep their current names and contents; this entry adds around them rather than
renaming anything.

## What makes the graph enforced rather than documented

`internal` by default, widening only where a declaration is genuinely public. A target cannot reach
another's internals, so an accidental dependency is a compile error rather than something a reviewer has
to notice. That is the enforcement; the diagram above is documentation.

## Why fine grain is affordable — measured

One target versus twenty changed spawn-to-exit by **0.067 ms**, inside noise, and what `ask` links costs
about **1.55 ms** over a trivial binary. So targets are free and link weight is not. ADR-0009 carries the
numbers and the white paper now says so.

**Scope of that measurement:** trivial modules, no static initializers, no globals, no Objective-C
classes, spawn-to-exit rather than spawn-to-first-frame. A module carrying heavy initialisation is not
covered.

## Done when

Six targets exist, the dependency graph compiles in that shape, the manifest header matches it, the gate
is green, and the four budgets have not regressed.