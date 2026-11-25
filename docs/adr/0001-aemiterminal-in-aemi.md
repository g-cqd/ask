---
status: superseded
superseded-by: ADR-0004
date: 2026-10-18
---

# 0001 — The terminal stack becomes `AemiTerminal`, inside Aemi

> **Superseded by [ADR-0004](0004-terminal-stack-seam-corrected.md).** The seam described here was
> assumed from the module list; probing the imports showed three further modules are inside it, and
> that Aemi is one package with many targets rather than a set of packages. The decision — the stack
> lives in Aemi, shared by all three projects — stands. The scope and the shape below do not.

## Context

Three projects need the same terminal stack, and two of them already have overlapping copies of it.

- **`Apps/KittyCode` in Atelier** — 16 modules, 125,059 lines of Swift in total. Of these the terminal
  stack is `KittyTerminal` (573 lines), `KittyCodecs` (1,815), `KittyRenderer` (1,142).
- **Atelier** — 24 modules in `Packages/AtelierCore`, some of which overlap the above.
- **`ask`** — needs a terminal stack and has none.

Duplicating the stack a third time is how the three drift apart.

## What already exists and is worth keeping

Verified by reading the code, not by assumption:

| Capability | Status |
|---|---|
| Synchronised output (DEC 2026) | Implemented **and on the hot path** — `RenderPipeline.flush()` wraps output in BSU/ESU, with `os_signpost` around every flush |
| Kitty graphics protocol, OSC 52 clipboard, OSC 99 notifications | Implemented |
| Focus events, bracketed paste, SGR mouse, alt screen, DECSTBM | Implemented |
| Double-buffered diff renderer, dirty tracking, `writeContiguous` zero-copy writes | Implemented |
| `EINTR` and short-write retry | Implemented |

## Gaps found

| Gap | Evidence | Why it matters |
|---|---|---|
| **No reset primitive at all** | `restoreMode()` restores only `termios`. No DECSTR, no RIS anywhere | A crash leaves the user's shell in alt-screen with mouse and paste stuck |
| **Kitty keyboard protocol only partly wired** | CSI-u exists in `KittySequences.swift:44`; no `modifyOtherKeys`, no progressive-enhancement flags | This is the fix for ESC-ambiguity latency |
| **Capability detection is env-var guesswork** | `TerminalCapabilities` reads `KITTY_WINDOW_ID` / `TERM_PROGRAM` only | Cannot detect DEC 2026 or keyboard-protocol support; silently degrades |

## Options

1. **`AemiTerminal`, a new package inside Aemi.** Name matches the existing tier convention
   (`AemiKernel`, `AemiText`, `AemiIO`, `AemiRuntime`, `AemiUnicode`, `AemiMetrics`, `AemiTestKit`).
   Aemi is already the agreed foundation, and Aemi already carries the strict kernel-tier settings.
2. **`TerminalKit`, standalone.** The name reads well in isolation, but breaks the `Aemi*` convention
   and needs its own repository, CI, and release cadence.
3. **Leave the stack in Atelier and path-reference it.** Cheapest, but makes Aemi depend on a git
   working copy, and inverts the dependency the ecosystem already runs on.

## Decision

**Option 1: `AemiTerminal`, a package inside Aemi.** The deciding factor is not the name; it is that
Aemi already publishes the strict settings tiers and the deterministic test kit the terminal work
needs, and it is the agreed foundation for `ask`.

`TerminalKit` is retained as the *umbrella product* name inside `AemiTerminal`, so both names the
owner prefers are kept and neither is lost.

Modules follow the same tiering Aemi already uses: `AemiTerminalCore` (connection, raw mode, the
reset ladder), `AemiTerminalCodecs` (sequences and decoders), `AemiTerminalRender` (screen buffer,
diff, pipeline).

## Consequences

- `Kitty*` module names become `AemiTerminal*`, which **touches Atelier** and its build settings. That
  is a real cost, accepted deliberately: it is the price of one stack instead of three.
- Aemi must be **tagged** before `ask` can depend on it by version. It currently publishes **zero
  tags**, which is a blocker, not a detail.
- The reset ladder and the active capability probe are new behaviour with no existing home, and they
  are written test-first against a PTY.