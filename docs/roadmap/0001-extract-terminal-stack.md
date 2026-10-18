---
status: done
blocked-by:
date: 2026-10-18
supersedes-scope-in: ADR-0001
closed-by: ADR-0010
---

# 0001 — Share the terminal stack through TerminalKit

Move reusable terminal implementations out of Atelier into TerminalKit (ADR-0005).
Aemi remains the source of generic kernel utilities.

**Closed in `ask` by [ADR-0010](0010-the-blocker-on-0001-did-not-exist.md).** The extraction itself is
done; the only remaining work was Atelier's consumer switch, which was always TerminalKit's entry to own
and never `ask`'s.

**Scope, corrected by probe.** The seam is **six modules, 6,263 lines**, not the three modules and
3,530 lines ADR-0001 claimed:

| Module | LOC | From |
|---|---|---|
| `KittyStyle` | 58 | `Apps/KittyCode` |
| `KittyTerminal` | 573 | `Apps/KittyCode` |
| `KittyCodecs` | 1,815 | `Apps/KittyCode` |
| `AtelierText` | 1,851 | `Packages/AtelierCore` |
| `KittyRenderer` | 1,142 | `Apps/KittyCode` |
| `KittyInput` | 824 | `Apps/KittyCode` |

`KittyEditor` (10,890 lines, sixteen dependencies) is **outside** the seam — it is the application
tier. ADR-0004 records how this was measured.

**Destination.** The `TerminalKit` repository, which now exists (ADR-0005): `TerminalKitStyle`,
`TerminalKitIO`, `TerminalKitCodecs`, `TerminalKitText`, `TerminalKitRender` and `TerminalKitInput`,
joining the `TerminalKitCore` already there. This is also where the package's first dependency
arrives — `KittyCodecs` and `KittyInput` both import `AemiKernel` — and not one moment before.

**Receiving side verified:** TerminalKit exports all six modules and now runs the inherited IO,
codec, input, renderer and text suites. Commit `4365a4d` reports 368 tests across seven targets
with explicit release testability. ADR-0012 there resolves the prior build blocker.

**Still required:** switch Atelier to the shared implementation, verify all affected consumers,
and remove duplicate implementation bodies. Compatibility module names may remain as re-export
shims; `TerminalKit/docs/roadmap/0003-atelier-consumes-terminalkit.md` owns that work.
*(That is TerminalKit's entry, not this one — see ADR-0010.)*

**Slicing.** `AtelierText` moves from `AtelierCore` and touches a different package, so it is a
separate commit from the Kitty modules. Behaviour changes are separate commits again: the DEC 2026
wrapping and the zero-copy writes are the load-bearing parts and must move unchanged.

**Risk:** renaming touches Atelier's build settings and CI. It is one commit per slice so the rollback
is a single restore.