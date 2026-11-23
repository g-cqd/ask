---
status: accepted
date: 2026-11-22
supersedes: ADR-0138 (its key derivation parameters; the rest stands)
---

# 0169 — Session keys derived at 64 MiB and 3 passes

## Context

ADR-0138 chose Argon2id at OWASP's minimum, 19 MiB and 2 passes, about 4 ms, and noted RFC 9106's second recommendation of 64 MiB.
The security audit of 2026-11-22 (HIGH-08) asked for 128 to 256 MiB. The owner asked for a sensible default.

Measured in release on an M3, medians of nine interleaved runs: 19 MiB × 2 passes 3.6 ms; 64 MiB × 3 passes 21.4 ms; 128 MiB × 3
passes 46.0 ms; 256 MiB × 3 passes 96.3 ms (diary 2026-11-22-05).

## Decision

New keys, and keys whose password is changed, derive their wrapping key at **64 MiB, 3 passes, 4 lanes**: RFC 9106's second
recommended choice. A guess costs about six times what it did. 128 MiB would take half of the start budget (ADR-0167) for less than
twice that, and 256 MiB all of it.

Keys made before keep the parameters stored with them in `keys.json` and open as they did; the bounds on parameters read from a file
(ADR-0138) are unchanged.

## Consequences

Unlocking takes about 21 ms, only after the person types the password, never at start with "remember". Its 64 MiB are wiped and
released as soon as the key is made, so the idle and active memory budgets do not see them.
