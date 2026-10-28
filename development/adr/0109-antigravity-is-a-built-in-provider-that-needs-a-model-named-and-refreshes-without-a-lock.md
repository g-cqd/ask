---
status: accepted
date: 2026-10-25
---

# 0109 — Antigravity is a built-in provider that needs a model named and refreshes without a lock

## Context

The decoder and encoder of ADR-0090 did nothing until something sent a request. This records the client, the access that keeps its
credentials current, and the wiring that makes `--provider agy` run, with what a real account did through the shipping binary on
2026-10-25 under ask's own identity.

## The probes

- **A tool call through the real agent loop** on `gemini-3-flash`, `claude-sonnet-5-5-low` and `gpt-oss-120b-medium`: each called `read`, was
  given the result and answered correctly. **Observed**, one prompt per model.
- **A three-step Gemini 3 loop** (`write`, `read`, `bash`) answered correctly, and its session file held **three** marked signatures, one per call.
  **Observed.**
- **Resuming that session in a new process** (`-c`) and asking for two more steps worked: the signatures were read back from the file.
  Asking the **same session on another Gemini model** (`gemini-3.5-flash-lite`) also worked, which is the sentinel path. **Observed**, one
  session.
- **Refresh through the binary.** The stored access token had expired (2,275 s ago). A run exchanged it: a new access token, the **same
  refresh token** (the second observation that Google does not rotate it), the client secret kept, file mode 0600, the Claude and Codex
  records untouched. **Observed.**
- **Onboarding is saved.** After the first run the record held the project and the tier (`free-tier`), so later runs skip the call. Its
  latency was **not measured**.
- **`ask models agy`** lists the 15 chat models with context and output limits, and names the server's default without using it. **Observed.**
- **`Scripts/probe-agy-provider.py`** (no network): a missing model exits 78 and names `ask models agy`; signed out exits 77 and names
  `ask login agy`; a file may not define `agy`; the known list names it; a damaged credential file is not "signed out". All six checks **fail**
  on the previous binary.
- **Budgets**, six interleaved pairs against `main`'s own build (12.18 MB; this is 12.27 MB, +86,608 bytes) at load 8 to 15: idle memory is higher
  in all six, median about **+56 KiB** (9.2 to 9.3 MiB, 9,392 to 9,504 KiB, against a budget of 24); cold start, input delay and action delay show no consistent direction once the order
  of each pair is reversed. Heavy load, so small differences are not certified.

## Decision

1. **`agy` is a built-in provider name.** A `providers.json` may not define it, and no named connection may take it.
2. **A model must be named.** The list carries a default (`defaultAgentModelId`, an Opus), and ask does not take it: it is the server's
   choice of what to spend the person's quota on, and nothing in ADR-0037 makes a list order a default. A missing model is exit 78 with the
   command that lists them.
3. **Access is one function of the clock.** A token is expired at its expiry, not after it. Google's refusal of the stored application
   secret (`invalid_client`) searches the installed `agy` once, tries once, and stores the secret that worked; a secret found a moment ago is
   not searched for again. `invalid_grant` is a sign-out and searches nothing. No lock is taken: the refresh token was not rotated in two
   observations, and a save is compare-and-replace, so a sign-in or sign-out made meanwhile stands. A refresh the server accepted whose save
   failed is kept in memory and saved on the next call (ADR-0082) and announced once (ADR-0091).
4. **The project is found once and stored with the credentials**, together with the tier, by the same compare-and-replace; a failed save
   costs one request.
5. **The request carries one `user-agent`, ask's own.** `ProviderEndpoint` gains an address given whole (the query is part of it), and an
   extra header replaces a default of the same name, whatever its case; before, it would have been sent twice.
6. **An explicit thinking level is refused** for Antigravity, as in ADR-0090.
7. **Failures are exit 77** (sign-in) or **78** (settings), as for the other providers.

## Consequences

- **No catalog cache, so no window.** Nothing at startup may touch the network, so the loop does not know the model's limits: it uses its
  16,384-token reply cap and compacts only when a request is refused for length. Cloud Code's wording for that refusal was **never
  provoked**, so `gpt-oss-120b` (131,072 tokens) may fail where the 1,000,000-token models do not. This is the next thing to build.
- Only `-p` was run. The interactive screen builds the same provider, but was **not exercised** with `agy`.
- Nothing in the first six probes provokes a refusal, a usage limit or a stream error from the server; those paths have synthetic tests only.
- Named Antigravity connections, a second account and `ask login agy --name` remain refused.
- The idle memory cost is small but not zero, and the repository has carried 100 to 170 KiB per feature before; it is a trend to watch.
