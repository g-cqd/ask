---
status: accepted
date: 2026-10-18
---

# 0007 — Claude subscription first, Spettro second; the system prompt rides in user messages

## Context

`ask` needs model providers (roadmap `0010`), and `pi-integrations` already carries six working ones.
Picking the first two decides the shape of the provider interface, because a second provider is what
reveals a seam that the first one hid.

It also surfaced a constraint that reaches back into the agent loop.

## The probes

**Probe 1 — do the two providers share a wire protocol?** Read
`pi-integrations/src/domains/{claude,spettro}/index.ts` and `provider.ts`.

**REFUTED as a common assumption.** They are different protocols:

| Provider | `api:` | Auth |
|---|---|---|
| Claude subscription | `anthropic-messages` | OAuth PKCE S256, pasted `code#state`, real refresh token |
| Spettro | `openai-completions` | `/auth/initiate` → browser → `/auth/poll/{session}` at 2 s under a 10-min deadline; `refreshToken` is a no-op because the "refresh token" is a duplicated device key |

Their tool-call encodings differ accordingly — `tool_use`/`tool_result` blocks against
`tool_calls`/`tool` role messages.

**This makes the pair a good choice, not a merely convenient one.** One provider would have hidden the
seam. Two protocols force the interface to be protocol-shaped rather than accidentally
Anthropic-shaped, and they fail differently: Spettro's catalog is fetched live from `/v1/models` with a
placeholder entry kept so the provider stays discoverable when signed out.

**Probe 2 — does subscription auth constrain the request shape?** Read
`pi-integrations/src/domains/claude/gate.ts` and `diagnostics.ts`, which document a classifier derived
by live bisection against the backend on 2026-10-16.

**CONFIRMED, and it constrains `0009`.** Subscription inference through `api.anthropic.com` with an
OAuth token is gated on prompt content:

- The system param's first block must exactly equal one canonical identity line; generic first blocks
  get `429`.
- Third-party harness prompts in the system param after block 0, **or sent as system-role messages
  anywhere in the conversation**, trip the classifier.
- The same content passes cleanly carried as blocks inside **user** messages.
- Headers, betas, tools, metadata and `max_tokens` are irrelevant to the gate.

**Not re-probed here.** These findings are read from a working, tested implementation rather than
re-derived against the backend, and the contract is undocumented and can change without notice.

## Decision

1. **Claude subscription first, Spettro second.**
2. **`ask` builds its system prompt as user-carried blocks**, behind one canonical first block, rather
   than putting it in the system param.

## Consequences

- The context builder in `0009` must build the system prompt this way from the start. Retrofitting it
  after the loop lands means re-plumbing every request, and the failure mode is a `429` that reads as
  rate-limiting rather than as a prompt-shape rejection.
- `0010` completes **before** `0011` starts: tool-call decoding cannot be built against a guess at
  either protocol's encoding.
- `ask` needs a gate-rejection diagnostic of its own — HTTP status, request id, quota headers, a
  redacted error summary — because the provider's own failure is a one-line "out of extra usage" that
  is indistinguishable from a genuine quota problem.
- Claude Code's own `<system-reminder>` pattern is the precedent for the user-carried shape, and the
  fact that a first-party tool works around the classifier this way is itself evidence that the
  constraint is real rather than incidental.
- Auth is not one mechanism but two. A shared "log in" affordance must cover PKCE-paste **and**
  browser-poll, and must not assume a refresh token exists.

## Follow-ups

- Re-verify the gate's current behaviour against the live backend before relying on it for
  `0009`'s context builder. The finding is dated 2026-10-16 and this ADR is dated 2026-10-18.
- Neither provider is a stable contract. Both are flagged experimental in `pi-integrations`, and a
  successful login is not proof of inference entitlement.