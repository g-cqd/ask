---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0027
---

# 0035 — Anthropic bearer tokens from the environment

pi accepts `ANTHROPIC_AUTH_TOKEN` (bearer, for gateways) and `ANTHROPIC_OAUTH_TOKEN` (a subscription token supplied
by a script). ask reads only `ANTHROPIC_API_KEY` and its own sign-in. Add both, in pi's order of precedence, with the
same rule ADR-0024 applies to the base URL: no credential over plain http to another machine.
