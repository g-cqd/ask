---
status: not-started
blocked-by:
prerequisites: ["ADR-0005"]
date: 2026-10-18
supersedes-scope-in: ADR-0001
---

# 0001 — Extract the terminal stack into Aemi

Move the terminal stack out of Atelier into Aemi, renaming `Kitty*` to `AemiTerminal*`.

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

**Done when:** Atelier builds and its existing tests pass against the Aemi targets; no `Kitty*`
terminal module remains in Atelier; `AemiTerminalCodecs` and `AemiTerminalRender` are exported.

**Slicing.** `AtelierText` moves from `AtelierCore` and touches a different package, so it is a
separate commit from the Kitty modules. Behaviour changes are separate commits again: the DEC 2026
wrapping and the zero-copy writes are the load-bearing parts and must move unchanged.

**Risk:** renaming touches Atelier's build settings and CI. It is one commit per slice so the rollback
is a single restore.