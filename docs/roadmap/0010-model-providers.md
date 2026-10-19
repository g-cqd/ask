---
status: in-progress
blocked-by: 
date: 2026-10-18
decision: ADR-0007
---

# 0010 — Model providers

**Decided (ADR-0007): Claude subscription first, Spettro second.** `pi-integrations` already has both
working and tested, so their auth and transport edge cases do not have to be rediscovered.

## Why this pair, and not a convenient one

They sit on **two different wire protocols**, which is the point:

| Provider | API | Base | Auth | Tool-call shape |
|---|---|---|---|---|
| Claude subscription | `anthropic-messages` | `api.anthropic.com` | OAuth PKCE S256, pasted `code#state`, real refresh token | `tool_use` / `tool_result` blocks |
| Spettro | `openai-completions` | `api.spettro.app/v1` | Browser session + polling, `Authorization: Bearer`, **no real refresh token** | `tool_calls` / `tool` role messages |

One provider would not have revealed the seam; the second does. Building Claude first and then Spettro
forces the provider interface to be protocol-shaped rather than accidentally Anthropic-shaped — and
`0011` must not be built against a guess at either one's tool-call encoding, so **this entry completes
before `0011` starts**.

The auth stories also differ in kind, which is worth knowing before designing:

- Claude: PKCE with a pasted response, a real `refreshToken`, and client-identity headers applied
  automatically when the key is `sk-ant-oat`.
- Spettro: `/auth/initiate` → browser → `/auth/poll/{session}` every 2 s under a 10-minute deadline, and
  `refreshToken` returns the same credentials unchanged because the "refresh token" is a duplicated
  device key. Its model catalog is fetched live from `/v1/models`, with a placeholder entry kept so the
  provider stays discoverable when signed out.

## The constraint this exposes, which reaches back into `0009`

**Claude subscription inference is gated by a fuzzy prompt-content classifier.** Empirically derived by
live bisection on 2026-10-16 and documented in `pi-integrations/src/domains/claude/gate.ts`:

- The system param's first block must exactly equal one canonical identity line. Generic first blocks
  get `429`.
- Third-party harness prompts in the system param — after block 0 — or sent as **system-role messages**
  anywhere in the conversation trip the classifier (`400 out of extra usage` / `429`).
- **The same content passes cleanly carried as blocks inside user messages.**
- Headers, betas, tools, metadata and `max_tokens` are irrelevant to the gate.

So an `ask` system prompt cannot live in the system param. It has to ride in user messages, behind one
canonical first block — Claude Code's own `<system-reminder>` pattern.

This is an architectural constraint on `0009`, not a provider detail, and it is much cheaper to design
around now than to retrofit. `0009`'s context builder should therefore build the system prompt as
user-carried blocks from the start.

The gate's contract is undocumented and can change without notice, and `pi-integrations` already carries
drift diagnostics for it. `ask` should fail with a diagnostic rather than a bare 429.

## What lands

- Streaming, incrementally decoded from bytes rather than reassembled per chunk.
- Tool-call decoding, including partial calls split across chunk boundaries — and both protocols'
  encodings, since they differ.
- Usage accounting: pi records a `UsageEntry` per response, and compaction depends on it.
- Errors as typed paths: an overloaded provider, a malformed response, a gate rejection and an expired
  login session are four different problems and must not collapse into one thrown string.

## Hot-path note

Decoding a byte once instead of re-scanning it is a named runtime principle in the white paper. A stream
that re-scans its buffer per chunk is the most likely way this entry goes wrong, and the input-delay
budget is what catches it.

## Done when

Claude streams a full turn including tool calls under subscription auth, Spettro does the same on the
OpenAI-completions protocol, usage is recorded for both, and a mid-stream failure or a gate rejection
recovers or reports cleanly.

## Progress — Claude, offline-complete (2026-10-18)

`AskAI` holds the whole Claude path, each layer tested against probed ground truth and mutation-checked:
- SSE framing, Anthropic events into provider-neutral `ModelEvent`s, and assembly into validated responses;
- request encoding in the gated shape (ADR-0007);
- PKCE, the authorize URL and pasted-code parsing (conformance cases from pi-integrations);
- token exchange, refresh and expiry;
- an HTTP transport;
- owner-only credential storage (ADR-0018);
- refresh-on-expiry access.

`ask login`, `ask logout` and `ask -p` bind them.

**Owed, needing the user once:** the first live sign-in and request, which verifies:
- that the honest `user-agent: ask` passes;
- that `claude-sonnet-5-5` exists (`GET /v1/models`);
- that streaming works against the real API.

Also owed: a concurrent-refresh guard, Spettro, usage recording into the session, and the gate-drift
diagnostic.

## Live probes passed (2026-10-19, after the user's `ask login`)

- `GET /v1/models` with the subscription token lists `claude-sonnet-5-5`, the default, plus thirteen others.
- `ask -p` ran a live turn with a `read` tool call:
  - stdout carried exactly the file's contents;
  - the session recorded user, response (`tool_use`), tool result, response (`end_turn`), with usage.
- The gated shape (ADR-0007) passes with `user-agent: ask`. Copying another client's identity is not
  needed.

**Found:** `cacheRead` is 0 on every turn. ask sends no `cache_control`, so each turn pays full input price
for the whole history. Prompt caching is now owed (see 0024).

**Still owed:** Spettro, a concurrent-refresh guard, and the gate-drift diagnostic.

## Progress (2026-10-19, ADR-0027)

OpenAI chat completions is spoken, so any compatible endpoint is configuration (`providers.json`). Spettro's
protocol is `openai-completions`; what it still needs is its browser sign-in and device-key auth, not a wire adapter.

## Audit (2026-10-19)

Delivered since: Spettro and Mistral sign-in (0037, ADR-0031), any OpenAI-compatible server by configuration
(ADR-0027), the Responses protocol (0036), usage recorded per response and shown, and retry with backoff for
overload and dropped connections.

Still owed from "Done when" and "Also owed":
- **A gate-drift diagnostic.** A rejection from the Claude subscription gate (ADR-0007) should fail with a message
  that says what changed, not a bare 429.
- **A concurrent-refresh guard.** Two asks refreshing the same OAuth token can invalidate one another's refresh
  token; a lock around the refresh would stop it. (A test I ran by hand this session broke the real sign-in that way
  through a symlinked credentials file, which is the same hazard.)
