---
status: not-started
blocked-by:
prerequisites: ["ADR-0001"]
date: 2026-10-18
---

# 0001 — Extract the terminal stack into `AemiTerminal`

Move `KittyTerminal`, `KittyCodecs` and `KittyRenderer` out of `Apps/KittyCode` into a new
`AemiTerminal` package in Aemi, renaming `Kitty*` to `AemiTerminal*`.

**Done when:** Atelier's `Apps/KittyCode` builds and its existing tests pass against `AemiTerminal`;
`Kitty*` terminal modules no longer exist in Atelier; `AemiTerminal` publishes `AemiTerminalCore`,
`AemiTerminalCodecs`, `AemiTerminalRender` and the `AemiTerminalKit` umbrella product.

**Notes:** the renderer's DEC 2026 wrapping and zero-copy writes are the load-bearing parts and must
move unchanged. This entry is a move, not a rewrite — behaviour changes belong in their own entries.
Refactor and behaviour stay in separate commits.

**Risks:** renaming touches Atelier's build settings and its CI. Roll back by restoring the modules,
which is why this is one commit.