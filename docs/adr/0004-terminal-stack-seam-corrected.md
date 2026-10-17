---
status: accepted
supersedes: ADR-0001
date: 2026-10-18
---

# 0004 — The terminal seam, corrected by probing

## Context

ADR-0001 proposed moving `KittyTerminal`, `KittyCodecs` and `KittyRenderer` into `AemiTerminal`, and
described `AemiTerminal` as a new package inside Aemi. Both statements were reasoned from the module
list rather than measured. Measuring them changed the answer.

## The probes

**Probe 1 — what does each module actually import?** `grep` of every `import` in the three modules:

| Module | LOC | Sibling imports |
|---|---|---|
| `KittyTerminal` | 573 | **none** |
| `KittyCodecs` | 1,815 | `KittyStyle`, `AemiKernel` |
| `KittyRenderer` | 1,142 | `AtelierText`, `KittyCodecs`, `KittyStyle`, `KittyTerminal` |

**REFUTED.** The seam is not three modules. `KittyStyle` and `AtelierText` are both required and
neither is in the list. A move of "the three terminal modules" would not have compiled.

**Probe 2 — how far does the closure actually reach?** Extending the same measurement to the newly
revealed dependencies, and to `KittyInput`:

| Module | LOC | Sibling imports |
|---|---|---|
| `KittyStyle` | 58 | none |
| `KittyTerminal` | 573 | none |
| `KittyCodecs` | 1,815 | `KittyStyle`, `AemiKernel` |
| `AtelierText` | 1,851 | none |
| `KittyRenderer` | 1,142 | `AtelierText`, `KittyCodecs`, `KittyStyle`, `KittyTerminal` |
| `KittyInput` | 824 | `KittyCodecs`, `KittyTerminal`, `AemiKernel` |

**CONFIRMED, with a correction.** The closure is **six modules, 6,263 lines**, not three and 3,530.
The good news is that it is genuinely closed: every external dependency is either standard library or
`AemiKernel`, which is *already in Aemi*. There is no path from the terminal stack out to
`KittyEditor`, which at 10,890 lines depends on sixteen modules and is the application tier, not the
terminal tier.

**Probe 3 — is Aemi a collection of packages?** Its own manifest states the rule: *"ONE package, MANY
small targets"*, and the kernel tiers (`AemiKernel`, `AemiText`, `AemiIO`, `AemiRuntime`,
`AemiUnicode`, `AemiMetrics`) are all **targets** in one `Package.swift`.

**REFUTED.** `AemiTerminal` is not a new package. It is a group of targets in Aemi's existing
manifest, which is also why the first slice could be landed there immediately.

**Probe 4 — does Atelier depend on Aemi by version?** `Apps/KittyCode/Package.swift:40`:
`.package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "85065dc1…")`.

**REFUTED.** Aemi is consumed by **pinned revision**, not by tag — which is why the zero tags are not
the blocker ADR-0001 called them. It also shows Atelier is on an older Aemi revision (`85065dc`) than
`main` (`47efa90`).

## Decision

1. The seam is **six modules, 6,263 lines**: `KittyStyle`, `KittyTerminal`, `KittyCodecs`,
   `AtelierText`, `KittyRenderer`, `KittyInput`. `KittyEditor` is explicitly outside it.
2. `AemiTerminal` is a **target group inside Aemi's single package**, following Aemi's own stated
   convention: `AemiTerminalCore`, then `AemiTerminalCodecs` and `AemiTerminalRender`.
3. Aemi is consumed by **pinned revision**, which is the mechanism already in use. Tagging Aemi is
   still desirable, but it is not a prerequisite and must not be described as one.

## Consequences

- The first slice has already landed: `AemiTerminalCore`, holding the tiered reset ladder, committed
  as `03ac1d5` with nine byte-exact tests.
- `AtelierText` moving from `AtelierCore` into Aemi is a **second, separate** move from the Kitty
  modules, and touches a different package. It is not bundled with them.
- The extraction is larger than ADR-0001 claimed by 79%. Any plan that quoted 3,530 lines was wrong,
  and so was the module list behind it.