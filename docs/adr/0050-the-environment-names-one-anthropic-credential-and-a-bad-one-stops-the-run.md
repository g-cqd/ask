---
status: accepted
date: 2026-10-20
---

# 0050 — The environment names one Anthropic credential, and a bad one stops the run

## Context

ask read only `ANTHROPIC_API_KEY` from the environment. pi also reads `ANTHROPIC_AUTH_TOKEN`, a bearer token for a gateway in front of
the API, and `ANTHROPIC_OAUTH_TOKEN`, a subscription token a script supplies (roadmap 0035). Three variables can all be set, and a
token goes into an HTTP header, where a newline is header injection. So two questions need an answer: which one wins, and what is a
token allowed to contain.

## The probes

Ledger in `docs/diary/2026-10-20-45.md`.

- **What order does pi use?** Read from pi-ai's own provider code: a stored credential, then `ANTHROPIC_AUTH_TOKEN` sent as
  `Authorization: Bearer` with no key header, then `ANTHROPIC_OAUTH_TOKEN` and `ANTHROPIC_API_KEY` as keys. Read, not run.
- **Does the real binary send what the order says?** A fake server on this machine recorded the headers for ten configurations. **CONFIRMED**:
  each variable produced exactly its headers, the auth token won over both others, an empty one did not mask a valid key, and four
  malformed tokens (a space, a newline, a carriage return, a non-ASCII letter) sent **no request** and exited 77.
- **Does each rule fail without its test?** 8 mutations, 8 killed.

## Decision

1. **Order among the variables:** `ANTHROPIC_AUTH_TOKEN`, then `ANTHROPIC_OAUTH_TOKEN`, then `ANTHROPIC_API_KEY`. The stored sign-in comes after
   all of them, as ask already had it for the key (pi puts a stored credential first; ask keeps the explicit environment above it).
2. **What each sends:** the auth token is `Authorization: Bearer` and nothing else that names a client (no subscription beta, no key
   header); the oauth token is a subscription bearer with the subscription beta, as the stored sign-in sends; the key is `x-api-key`.
3. **An empty variable is unset**, so it cannot mask a valid one below it.
4. **A set variable that is not a plain token refuses the run** (exit 77) before any request, and the run does **not** fall through to a
   lower variable: sending a credential the user did not choose is the worse failure. A plain token is 1 to 4096 characters of visible
   ASCII (no space, no control character, nothing outside ASCII). The message names the variable and never the value.
5. **A named connection ignores the environment** (ADR-0048), and `ANTHROPIC_BASE_URL` keeps its existing rule (ADR-0024): honoured over
   https, or over http to this machine, so a bearer token cannot be sent unencrypted to another host.

## Consequences

- Workload-identity federation, which pi also supports, is not built.
- A token with a legitimate space or a trailing newline from a careless `export` is refused, loudly, with the variable's name. That is a
  small inconvenience traded for never splitting a header.
- Not verified live: that api.anthropic.com or a real gateway accepts these headers from an environment token. The stored sign-in sends
  the same headers, and the fake-server probe proves the wire, but no real account was used with an environment variable.
