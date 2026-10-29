---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0144 — Investigate why the Claude connector uses extra usage

Owner report (2026-10-29): Claude-connected ask is using extra usage; proxy the real Claude Code client to understand what differs. This
is the top priority, ahead of UI changes and memory work. A request accepted by the API does not prove subscription billing.

## Established so far

- Installed Claude Code: `2.1.312`, `/opt/homebrew/bin/claude` (Homebrew Cask).
- Ask's subscription request: `AnthropicClient.oauthBetas` has `claude-code-20250219,oauth-2025-04-20`, user-agent `ask`;
  `AnthropicRequestEncoder` sends its fixed Agent SDK identity line as system and carries ask's instructions in the first user message.
  These are source observations, not a diagnosis of billing. Older comments that headers do not affect the subscription gate do not prove
  today's billing behaviour.
- No live inference, token refresh, packet capture or proxying was performed for this investigation yet. Do not infer the cause from a
  user-agent or a system line alone: account limits, model entitlement and extra-usage policy must also be checked.
- REA `6.8.0` installed from npm `rea-agents` (repository `morluto/rea`), with installation scripts disabled and optional dependencies
  omitted, at `~/.local/share/ask-tools/rea-6.8.0`. Node `v26.12.1` meets its engine requirement. Ask launches the absolute Node and entry
  script paths, not a package runner. All 229 MCP tools are reachable; initialize and tools/list, and ask's `/mcp`, verified.
- Existing apple-docs, Xcode and LLDB settings preserved. Configuration backup: `~/.config/ask/config.json.before-rea-20261029`.
  Reload this session to obtain REA. Optional Frida and analysis engines have not been installed or verified.

## Investigation order

1. Capture a minimal request from the current official client to a **localhost sink, no forwarding**, with dummy credentials, no tools,
   no repository context and isolated settings. Compare the request shape with ask's encoder. Verify that the chosen client mode actually
   exercises OAuth; a dummy API-key request is not evidence of the OAuth path.
2. Check account identity, model entitlement, quota exhaustion and extra-usage policy without logging credentials or changing settings.
3. If needed, a tightly scoped proxy of the owner's real official-client request, explicitly distinguishing captured facts from hypotheses.
   Bind loopback only; keep TLS verification upstream; do not install a system-wide trust exception. Redact Authorization, cookies, tokens,
   account identifiers and unrelated traffic before writing anything. Never commit raw captures.
4. Agree on a minimal potentially billed live test before forwarding inference. Compare model, headers, body, relevant response headers,
   quota information and actual usage classification; an HTTP 200 or token count is not proof of how it was billed.
5. Fix only what evidence supports, with tests. If the server does not support subscription access for this integration, say so rather than
   claiming that mimicking identity guarantees it. Do not silently fall back from subscription to paid API/extra usage.

## Owner offers a controlled live session (2026-10-29)

Open Kitty with proxied Claude Code in a disposable copy of a repository, so destructive experiments do not touch the original. Proposed
fixture: a local clone of ask at the recorded revision (no credentials, session stores or untracked files copied). Keep scratch output and
captures outside the source repository. Scope the proxy environment to that terminal, never the global shell or system proxy. Coordinate
the first forwarded inference with the owner: even a minimal request might be billed as extra usage. Record upstream and downstream
request/response differences without treating a successful response as proof of subscription billing. Kitty is installed; no terminal or
proxy has been started yet. Reload first to make the newly installed REA tools available to this agent.

## Expanded API research (owner, 2026-10-29)

Capture which APIs the official client actually uses for usage, quota and adjacent account behaviour, not only Messages inference.

### Scope

- Usage and quota: utilization windows, reset timestamps, per-model limits, throttling, and whether figures come from separate requests,
  inference response headers, or local calculations. Preserve the distinction between tokens, percentages, currency and plan allowances.
- Extra usage: enabled/disabled status, available balance or spending limits when returned, and any explicit evidence of how a request was
  classified. Do not infer paid fallback solely from a successful response or a depleted subscription window.
- Account and subscription: plan/organization selection and model entitlement, with identifying values redacted.
- Model discovery and relevant remote configuration/feature checks that could affect inference, quota presentation or routing.
- Auth lifecycle: endpoint and flow shape if observed, never token values. Do not initiate login, logout or token rotation just to capture it.
- Other calls: classify telemetry, updates and ancillary traffic by purpose; do not reproduce those calls merely to imitate the client.

### Capture matrix and deliverable

Observe startup/idle, the client's usage and status views (such as `/usage` and `/status`, if present), model selection, one agreed minimal
inference and any naturally occurring limit/error. Do not deliberately exhaust quota. Compare with ask using the same account and exact
model only when this can be verified safely; otherwise label that comparison unmatched.

For each observed endpoint, record method, host/path with identifying path/query values removed, triggering action, auth **kind**, required
header names, redacted request/response shape, relevant quota/header fields, units, refresh/cache cadence if observed, and response/error
semantics. Mark evidence as live-observed, statically found, or hypothesis. Static discovery alone does not establish that a call is used,
read-only, available to ask, or relevant to billing. No finding is established yet.

Produce a sanitized endpoint inventory and a gap table against ask: already implemented, safe read-only candidate, unsupported/private or
unresolved. Prefer documented APIs where available. Any adoption needs bounded refresh/backoff and no launch/input latency regression.
A passive capture of an official-client action is distinct from replay: do not replay billing changes, top-ups, spend-limit edits, account
changes or unknown mutations. Keep credentials, cookies, account identifiers and unrelated project content out of durable capture records.

## Callback hypothesis and first lab setup (2026-10-29)

Owner supplied the official client's authorization URL: same OAuth client ID and scopes as ask, but a dynamic localhost callback rather
than ask's hosted callback/manual paste. State and PKCE values are deliberately not retained. The different callback explains automatic
completion versus pasting a code; whether the grant or billing classification differs is **unproven**, and is now a comparison axis.
Do not reauthenticate the baseline merely to test it; any grant-flow experiment must account for credential rotation and keep existing
ask sessions intact.

First-stage lab prepared: independent ask clone at `~/Developer/ask-lab/ask`, origin removed; private versioned Python environment with
mitmproxy 12.2.3. Loopback proxy permits only api.anthropic.com HTTPS GET/HEAD, rejects inference and token-exchange POSTs and other hosts.
Client network sandbox permits only the proxy's localhost port. Per-process CA trust only, upstream TLS verification on, no global trust
or proxy changes. Local tests verify a blocked inference response, omitted sentinel credentials/prompts, and refused direct-IP egress.
Sanitized JSONL and transformed HAR preserve field shapes and selected quota values, not raw bodies or credentials. These restrictions
alter normal client behaviour; a missing request can reflect a block, and this first stage is not a faithful inference/billing test.

## First read-only result (2026-10-29)

Owner: status and usage work, ordinary prompt fails (blocked as designed). `/api/oauth/usage` returns 200, five-hour utilization 2%,
seven-day 9%, `extra_usage.is_enabled: false` for the official client's current login. Account equivalence with ask is unverified.
Three inference POSTs (different shapes, including auxiliary-looking work) were blocked before forwarding, not evidence of upstream
rejection or billing. REA MCP successfully parsed the sanitized, URI-valid HAR export (29 records). Full findings and limits:
`development/research/claude-usage-observations-2026-10-29.md`. No inference enabled, no credentials refreshed or billing settings changed.
