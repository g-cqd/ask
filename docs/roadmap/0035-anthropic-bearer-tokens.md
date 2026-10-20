---
status: done
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0035 — Anthropic bearer tokens from the environment

pi accepts `ANTHROPIC_AUTH_TOKEN` (bearer, for gateways) and `ANTHROPIC_OAUTH_TOKEN` (a subscription token supplied
by a script). ask reads only `ANTHROPIC_API_KEY` and its own sign-in. Add both, in pi's order of precedence, with the
same rule ADR-0024 applies to the base URL: no credential over plain http to another machine.

## Done (diary 45, ADR-0050)

Both variables, in pi's order, with the base-URL rule unchanged; an empty variable is unset; a value that is not a plain token stops
the run before any request. Verified on the real binary against a fake server (`Scripts/probe-anthropic-env.py`) and by 8 mutations.
Not done: workload-identity federation. Not verified: acceptance by the real API or a gateway.

