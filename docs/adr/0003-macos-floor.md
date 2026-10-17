---
status: accepted
date: 2026-10-18
---

# 0003 — Platform floor is macOS 26

## Context

`ask` is macOS-only. The floor was an open question: the toolchain is Swift 6.4 on Xcode 27 with the
macOS 27 SDK, and a higher floor buys newer APIs without availability guards.

## The probe

All three candidate floors were built and the full suite run at each, changing nothing but the
`platforms:` line:

| Floor | Build errors | Test run |
|---|---|---|
| `.macOS(.v15)` | 0 | 6 tests, 2 suites passed |
| `.macOS(.v26)` | 0 | 6 tests, 2 suites passed |
| `.macOS(.v27)` | 0 | 6 tests, 2 suites passed |

**Nothing in the package requires anything above macOS 15 yet.** The floor is therefore currently a
free choice, and not a constraint — which is itself worth knowing, because it means the floor can be
decided on reach rather than on necessity.

## Decision

**`.macOS(.v26)`.**

macOS 27 buys nothing today: the probe shows no code needs it. macOS 26 is one major behind the
current SDK, so it reaches a wider set of machines for no capability `ask` actually uses. Choosing
the newest floor for its own sake would exclude users to buy nothing.

## Consequences

- When something genuinely requires a newer API, the floor moves and an ADR records the probe that
  justified it. It is a one-line change, deliberately left cheap.
- The strict features in play (`StrictMemorySafety`, `.v6` strict concurrency, `ExistentialAny`) are
  **compile-time**, not OS-versioned. They do not justify a higher floor.
- This ADR should be re-probed, not re-read, if the SDK moves. The claim "nothing needs 27" was true
  on 2026-10-18 and is not a permanent fact.