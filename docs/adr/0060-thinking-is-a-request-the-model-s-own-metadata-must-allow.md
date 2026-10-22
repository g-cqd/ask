---
status: accepted
date: 2026-10-22
---

# 0060 — Thinking is a request the model's own metadata must allow

## Context

Providers disagree about what "thinking" is. The research (`docs/research/thinking-controls-2026-10.md`, diary
2026-10-22-07) found, by running the reference client and by small requests with ask's own credentials:

- Claude Sonnet 5.5 refuses `thinking: disabled` with a 400 that says to send `between_tools`; Sonnet 4.6 accepts
  `disabled` and refuses `between_tools`. "Off" is a property of the model.
- The Codex catalog advertises `ultra` for gpt-6.1-sol, and inference refuses it (400); `none` and `minimal` are
  refused too. A catalog is not proof of acceptance.
- Sonnet 5.5 reports `enabled` unsupported and still accepts a 1024-token budget. Reported capabilities are the
  preferred modes, not every accepted syntax.
- Anthropic's authenticated `GET /v1/models` states thinking modes and per-effort flags, so no model-name table is
  needed.
- A real signed thinking block replayed unchanged under a different effort (adaptive low, between_tools) was accepted.

## Decision

1. **The user states a level; AskAI chooses the wire control.** `ThinkingLevel` is `default`, `off`, `minimal`, `low`,
   `medium`, `high`, `xhigh`, `max`. `ultra` is deliberately absent. `default` sends nothing and is not "off".
2. **Unset and `default` are byte-identical to before.** They do no discovery, add no request field and no screen text.
   `default` given explicitly still overrides a lower configuration layer (file < environment < flag).
3. **Native Claude selection reads the model's own capabilities.** Off is `disabled` or `between_tools` according to
   what the model reports; a named effort needs adaptive thinking and a reported effort; a model reporting only
   `enabled` gets a concrete token budget (a client policy of 1/2/8/16/32/64 Ki, always leaving 1024 for the answer,
   shown to the user), plus an effort only when that model reports it. Unknown capabilities refuse; they are not guessed.
4. **No clamping and no remapping.** A level the model does not offer is an error that names what it does offer, before
   any inference request.
5. **Responses endpoints** receive `reasoning.effort` (and `summary: auto`, or `none` for off). Their support is
   reported as unverified unless a catalog lists the level; a server may still refuse it, and the status line says so.
6. **Chat-completions endpoints refuse** an explicit level: no portable field has been observed, and silently
   ignoring the setting would be worse than refusing it.
7. **Loading never touches the network.** Startup, `ask config` and `/model` read only a cached descriptor. A native
   Claude model with none has its control looked up just before the first request, by a provider wrapper
   (`DeferredThinkingProvider`) that keeps a successful result and retries a failed one. The lookup failing, or the
   model lacking the level, ends that request before inference and says why; the setting is never quietly dropped.
   Probed: a miss on the load path cost a median 24.7 ms against 13.2 ms unset on loopback alone, which would
   consume the whole 25 ms cold-start budget before any real network time (diary 2026-10-22-07).
8. **Native discovery is cached under the current authorization.** Scope = endpoint, registration, and a SHA-256
   fingerprint of the authorization kind and value. The raw credential is never stored. A refreshed or replaced grant
   misses the old file; sign-out finds none. An incomplete download is shown but never replaces a complete cache. An
   address with user information, query or fragment is not cached.
9. **Provider mapping lives in AskAI.** The loop carries one opaque `ThinkingControl` on every request, including
   tool turns and summarisation requests; the terminal only displays the configured level, its source and its status.

## Consequences

- A catalog-selected control is reported as "catalog-selected … server may still refuse", never as verified.
- A token refresh changes the authorization fingerprint, so a nondefault level after a refresh costs one metadata
  request at the next first request (not at startup). That is a deliberate price for never relying on a stale grant's
  metadata. A first, deferred request is sized with the default reply limit; later cached starts use the model's.
  Notices the lookup produces (a partial list, a damaged cache) are not shown on that path yet.
- `ask models anthropic` lists real limits, modes and efforts, and refreshes the cache.
- Not established: that a legacy budget level is equivalent across models, any quality, cost or latency benefit,
  between-tools thinking updates in a real tool loop (zero were observed), cross-model signed-block replay,
  concurrent Claude refresh (0044), real two-account separation, live pagination parameters, and thinking controls
  for any chat-completions server.
- `/reload` forwards the flag to a replacement process, and cancelling during the deferred lookup is meant to prevent
  the request; neither has an executable test (the `ask` target has none, and the cancellation path has no
  deterministic hook).
