---
status: done
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

## Inference test authorization and harness correction (2026-10-29)

Owner supplied ask's exact provider refusal: HTTP 400, "You're out of extra usage. Add more at claude.ai/settings/usage and keep going."
This is a reported upstream refusal, not a lab response, but it does not establish why extra usage applies or account/model equivalence.
Owner approved potentially billed inference through ask or Claude Code. First single-request guard matched the exact prompt text in the
last user message; the actual client request missed it and received a local 403. Permit remained unused: no inference forwarded. Claude
suggested `/login` in response to our local refusal, which was misleading. Do not reauthenticate on that basis.

Harness correction: locally blocked requests use 400 invalid_request_error, not an auth-looking 403. One single-use permit now allows
POST /v1/messages only for a streaming conversational request with the Claude Code beta flag and without a structured-output format.
Auxiliary/minimal calls, token refresh and other POSTs remain blocked. This predicate is an experimental harness filter, not provider
billing logic. Retrying the small agreed prompt is the next step; upstream acceptance/billing still untested.

## Official-client baseline succeeded (2026-10-29, 14:54)

One authorized request, `claude-opus-5-5`, returned 200 and the owner saw OK. Unified response headers: status allowed, five-hour/seven-day
allowed, representative claim five_hour, overage rejected with org_level_disabled. This supports a subscription-quota baseline, not yet
account/model equivalence with ask. Later local 400 refusals occurred because the one-use permit had been consumed; no reauthentication
needed on that evidence. Details and token counts are in the research note. Next: compare ask's exact failing request, same model and
verified account/grant where possible; do not blindly copy first-party identity headers or conclude that callback shape causes billing.

## Matrix and interactive lab (2026-10-29)

All four small tool-history/default-or-medium thinking cases succeeded against five_hour quota, overage rejected. Offline reconstruction of
historical boundaries 6488/6490 found no recovery issues or RequestContext repairs; encoded context about 0.94 MB without tools/system.
Not sent upstream. User requested interactive ask: fresh disposable clone in Kitty, real CLI/built-in tools, Opus medium, eight inference
requests total (four per turn), restricted network, no MCP/skills/credential refresh. No automatic replay of the long session. Research note
holds exact matrix, reconstruction counts and harness limits. Await interactive outcome, then capture the exact failing request if needed.

## Interactive ask result (2026-10-29)

Owner completed two turns: seven requests, seven HTTP 200 responses, actual read (3) and bash (4) calls, successful signed-thinking/tool-result
replay. Context 7.2k to 10.2k tokens. Every response uses allowed five_hour quota with overage rejected. Remaining inference budget revoked.
The original extra-usage refusal is not reproduced; original long-context replay is not yet performed or assumed cheap. Research note has
counts, sizes and remaining variables. Next: obtain the failing process's effective settings and bounded request metadata; any historical
reconstruction is approximate without its tool/config snapshots.

## /tree is the reported trigger

Owner reports the refusal follows /tree checkout. Local full-log checkout to 6485 versus historical-prefix reconstruction yields identical
encoded context, before and after an identical new prompt. No future-branch leakage established. Current runtime settings persist across
checkout, so historical settings mismatch remains a variable. Two-request small-lab live checkout test prepared in `Ask tree lab`, resuming
only the successful small session. No original-session inference or reauthentication. Research note records limits; outcome pending.

## Reproduced upstream after long-history checkout (2026-10-29)

Owner submitted the historical prompt in the copied session, after approving a larger proxy allowance. One forwarded ask/Opus request,
960643 body bytes, 169 thinking blocks and 194 tool-call/result pairs: Anthropic HTTP 400 invalid_request_error with the exact reported
out-of-extra-usage sentence, header overage-disabled-reason org_level_disabled. Not a local proxy error. Small checkout succeeded; long
checkout fails. No causal attribution yet to /tree, token threshold, signatures or callback. Research note separates earlier local refusals
from this upstream reproduction. Preserve fixture and isolate variables; avoid repeated large-context requests without a clear test.

## Root cause isolated (2026-10-29)

Anthropic's endpoint rejects requests that define tools named `mcp_search` or `mcp_call` under this OAuth grant, returning HTTP 400
with the extra-usage refusal. Renaming them (for example to `search_catalog` and `dispatch_call`) succeeds against subscription quota
with the exact same schema and description; changing only the description while keeping the names fails. The issue appeared after /tree
because MCP servers had just been configured in that session. Resolution requires compliant tool names across AskTools and documentation.

## Compatibility-layer request and connection observations (2026-10-29)

The owner requested a layer reproducing how Claude Code transmits tool calls, informed by examining the Claude Code binary.
No compatibility layer was implemented.
The experiments found that changing only two tool names moved the same request from an extra-usage refusal to subscription
quota, without a validation error. The binary was not disassembled; later the same day `strings` was run over it
to list its tool names for feature research (0146).

`AnthropicRequestEncoder.canonicalSystemLine` sends a "Claude Agent SDK" identity line, and the
`claude-code-20250219` beta header, on subscription requests. These remain request-comparison observations.

Other available connections are an Anthropic API key (`ask login`, billed per use) and the existing Copilot connection for
Claude models. The ask-side error improvement is to describe the subscription refusal plainly instead of implying exhausted
quota. Private lab data (session copy and sanitized captures) remains in `~/.local/share/ask-lab`, outside git.

## Confirmed from a second session (2026-10-29)

With throwaway configurations (the owner's file untouched): apple-docs alone, lldb alone, and Xcode's 54 tools offered directly are
accepted; any configuration that offers `mcp_search` and `mcp_call` (Xcode or REA in search mode, lldb forced to search mode) gets the
refusal. Only the request's `tools` list matters: a history that called `mcp_search` is accepted once the tool is not offered.
Today the owner's running configuration offers only apple-docs (9 tools, direct), which is
accepted; Xcode, LLDB and REA are commented out by the owner.

## The honest message, built (2026-10-29)

`AnthropicStreamDecoder.notCovered`: an HTTP 400 `invalid_request_error` whose words say "out of extra usage" now reads "Anthropic did not
count this request against your Claude subscription, and extra usage is off, so it refused it (your five-hour quota still allows requests).
Sending it again will not help; an Anthropic API key or another connection can serve it. Anthropic said: …". The quota clause appears only
when the response's `anthropic-ratelimit-unified-5h-status` header says `allowed`. The kind stays `invalidRequest`, which is not retried.
Tests: `AnthropicSubscriptionRefusalTests`. Not checked against a live refusal after the change.

## The tool names, renamed (2026-10-30, close-out pass)

The root cause above was found on 2026-10-29 but the names had not changed: any configuration putting an MCP server in search
mode (more than 16 tools, as Xcode's 54) had every request on a Claude subscription refused. `mcp_search` and `mcp_call` are now
`search_catalog` and `dispatch_call`, the two names checked live to pass; a comment on `MCPCallTool` says why, and `probe-mcp.py` checks the
old names are never offered. Sessions that called the old names still replay (the history is accepted once the tools are not offered).

Still owed: one live request with a search-mode server on the subscription (the owner's step); a general message for a refusal from the
subscription gate (moved here from 0010); the naming table's row 40 lets the owner choose other names after a live check.

## Confirmed live (2026-10-30)

The owner enabled Xcode's MCP server (54 tools, so search mode) and used every connected tool on the Claude subscription for a long
conversation: no refusal. The renamed `search_catalog` and `dispatch_call` pass. The general message for a refusal from the subscription
gate moves to 0165.

