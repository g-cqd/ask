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
