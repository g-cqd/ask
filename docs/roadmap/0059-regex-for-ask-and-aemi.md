---
status: not-started
blocked-by: []
date: 2026-10-24
---

# 0059 — A safe regex for ask, and possibly `AemiRegex`

Owner decision (2026-10-27): use AemiRegex, including a repo-wide migration of
Swift Regex. The actionable migration is now roadmap 0077; the wrapper/engine
stages below are retained as the original investigation's alternatives, not the
current implementation plan.

Today `ask` has one runtime regex use (three short patterns on a refusal message in `ProviderFailure+Overflow.swift`) and two test helpers,
all in Swift `Regex`. The owner asked for a Sendable, safe `NSRegularExpression` wrapper to remove it, and asked what a vector kernel and a
standalone `AemiRegex` would need. The answer, with measurements, is `docs/research/aemiregex-requirements-2026-10.md`; the probe ledger is
diary 2026-10-24-39.

## Done

The measurements and the report only. No code.

## Still owed

In order, and each only when the owner has decided the questions in section 6 of the report:

1. **Stage 0 (in `ask`)**: a wrapper over `NSRegularExpression` with typed errors, a `String.Index` result and a deterministic progress guard
   scaled to the input; replace the five uses. Still to measure first: the guard's budget against benign and catastrophic calls per position,
   the first-use cost of ICU on the refusal path, and the binary-size change.
2. **Stage 1 (Aemi)**: the Swift SIMD prefilter, repeated on a native x86_64 host.
3. **Stage 2 (Aemi)**: a linear-time engine behind a differential oracle.

Assembly is not on the list; the report says what measurement would put it there.
