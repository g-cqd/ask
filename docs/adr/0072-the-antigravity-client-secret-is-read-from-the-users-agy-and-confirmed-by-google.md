---
status: accepted
date: 2026-10-23
---

# 0072 — The Antigravity client secret is read from the user's `agy` and confirmed by Google

## Context

Roadmap 0052 asks for an Antigravity connector. Its sign-in is a Google OAuth authorization-code flow for a Desktop-type client,
and Google's token endpoint refuses that client without its secret. The secret identifies the application, not a user. The
owner decided that using it is acceptable, stating that Google itself does not treat an installed application's secret as
secret, and allowed upgrading the installed `agy` if useful. pi-integrations already finds it by scanning the installed binary; the
evidence rule says its code is run against edge cases before anything is adopted (diary 2026-10-23-21).

## The probes

- **The binary holds the secret, and naive matching returns a wrong value.** In `agy` 1.4.2 there are three `GOCSPX-` strings; the
  greedy run at the first is 70 bytes (two secrets with nothing between them), a value that is in no file. **CONFIRMED.**
- **Shape does not identify it.** Of the three 35-byte candidates, Google's token endpoint answers `invalid_grant` (HTTP 400) for
  exactly one and `invalid_client` (HTTP 401) for the other two. **CONFIRMED**; a decoy has the right shape.
- **Upgrading changes it?** `agy update` moved 1.4.2 to 1.4.6 (186,590,176 to 189,329,424 bytes). The same three candidates, the same
  accepted one (SHA-256 prefix `1d2f0410` before and after). **REFUTED** (it does not change); extraction still works.
- **Does ask's own code agree?** The Swift finder scanned both versions in 0.15 and 0.26 s without holding the file in memory,
  and the live verification took 0.35 and 0.39 s (at most three requests), both accepting the same candidate.
- **Does each rule fail without its test?** Deliberate faults in the finder, the locator and the verifier, against a baseline
  proven green first (diary).

## Decision

1. **Read it from the user's own installed `agy` when it is needed.** The binary is found from `AGY_BINARY`, then `$PATH` (`agy`, then
   `antigravity`), then the usual install places. It is scanned in pieces for `GOCSPX-`, sliced to the widths a secret has, exact length
   first. A scan never holds the binary whole.
2. **Only Google's answer pairs a candidate with the client.** A probe sends the client id, the candidate and a code that cannot be
   real; HTTP 400 `invalid_grant` is the pairing, `invalid_client` a rejection, and anything else stops the search, because it says
   nothing about the pairing and guessing on would misattribute it. At most 16 probes are sent.
3. **It is never bundled, never printed, never in an error message.** No failure description can carry a candidate; the probe's
   output is a hash prefix.
4. **No `agy`, no sign-in.** The refusal says so and names `AGY_BINARY`.

## Consequences

- A user who has not installed `agy` cannot sign in to Antigravity through ask. That is deliberate: the alternative is shipping an
  application credential in this repository.
- If a future `agy` drops or changes the string, sign-in fails with `notVerified` rather than with a guess.
- **Not decided or done:** where the verified secret is kept between a sign-in and a refresh (rescan each time, or store it with the
  credential and rescan on `invalid_client`), the sign-in itself, onboarding, the model list and streaming. And one question for
  the owner that no probe can settle without a signed-in account: pi found that the backend gates the full model catalog and model
  routing on a User-Agent starting with `antigravity/cli/`, a first-party identity claim. ask's rule elsewhere is to identify itself
  honestly (ADR-0007). Probing whether an honest identity works is the first live step; the answer, and the owner's choice if it does
  not, belong in a new record.
