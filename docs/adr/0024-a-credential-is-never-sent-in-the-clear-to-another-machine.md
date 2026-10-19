---
status: accepted
date: 2026-10-19
---

# 0024 — A credential is never sent in the clear to another machine

## Context

Every request to the provider carries a bearer credential: an API key or a subscription's OAuth token.
`ANTHROPIC_BASE_URL` (read as the official SDK reads it) moves where requests go, and `AnthropicClient.endpoint`
accepted any value that parsed with a scheme. The variable is process-wide and is often set by a shell profile
or a tool the user did not read.

## The probes

- **`http://gw.example`, `http://10.0.0.5:8080`, `ftp://…` and `file:///…` were all accepted** and would have
  carried the credential. Probed by writing the refusals as tests first; the refusals failed, the loopback
  acceptances already passed.
- **`http://localhost.evil.example`** is the case a prefix check gets wrong; it is refused because the host is
  compared whole.
- **A value with userinfo** (`http://user:secret@host`) must not appear in the explanation: the message names the
  variable and the reason and never the value.

## Decision

1. `ANTHROPIC_BASE_URL` is honoured for `https` to any host, and for plain `http` only when the host is
   `localhost`, `127.0.0.1` or `::1`. A local gateway and a test server keep working.
2. Anything else is ignored and the official endpoint is used: the safe direction, since the credential then goes
   only where it was issued. The reason is `AnthropicClient.endpointProblem(environment:)`, which never echoes
   the value.
3. A refusal is never silent: the composition root shows `endpointProblem` to the user. **Not done yet**
   (roadmap 0028): `Composition.swift` was being rewritten on another branch, and editing it here would have
   made that work unmergeable. Until then the fallback is safe but unannounced.

## Consequences

- A gateway on a private network over plain `http` no longer works until it offers `https`. That is the cost,
  and the reason is written here, as the project requires of any refusal.
- The bash tool still passes the process environment, including `ANTHROPIC_API_KEY`, to commands. That is a
  sandboxing question (ADR-0020), not settled here.
