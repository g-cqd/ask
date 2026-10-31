---
status: done
blocked-by:
date: 2026-10-19
decision: ADR-0020, ADR-0136
---

# 0021 — Network by domain, through a local proxy

Seatbelt sees IPs and ports, not names (probed). Domain-level network control therefore needs a proxy, as
Claude Code does:
- an HTTP CONNECT and SOCKS proxy inside ask, allowing the policy's domains;
- child processes allowed only `localhost:<proxy port>`;
- `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` set for them.

## Open questions, each needing a probe

- Tools that ignore proxy variables: these fail closed. Is that acceptable?
- Certificate pinning.
- Local port binding (`allowLocalBinding`).

## Owner (2026-10-31): a provider-only level

Add a network level where commands reach only the model provider's server (the signed-in providers' hosts), alongside `none`,
`localhost` and `any`. It needs this proxy, because the macOS sandbox can only allow every host or none.

## Done (2026-10-31): the provider level (ADR-0136)

- `SandboxPolicy.Network.provider` sits between `localhost` and `any`. Its Seatbelt profile is `localhost`'s. Config, flag and
  per-call requests accept it, and the setting catalog lists it.
- `ProviderProxy` is an HTTP CONNECT proxy on 127.0.0.1 with blocking POSIX sockets, one thread per tunnel. `ProxyRequest` decides
  each request: a tunnel to an allowed host and port, else 403, 405 for other methods, 400 for a malformed head. The run's
  provider is the allow list (`ProviderServer`, set through `ProviderAccess` whenever the run settings resolve). A job under the
  level gets the proxy variables, and the proxy starts on first use.
- Tests, written first:
  - `ProviderNetworkLevelTests`: the name, the ordering, and the Seatbelt lines in both bases.
  - `ProxyRequestTests`, `ProviderProxyTests`: a real socket, an echo server as the provider, a relay and a refusal.
  - `ProviderNetworkJobTests`: a real sandboxed `bash`, which gets the variables and the 403.
  - `ProviderServerTests`.
- Live: Anthropic reached (401 without a key), example.com refused (403), and a direct connection cannot resolve the host.
- Answers to the open questions:
  - Tools that ignore the proxy variables fail closed.
  - Certificate pinning is untouched: TLS passes through the tunnel.
  - Local port binding is as at `localhost`.
- Not done: SOCKS; the other signed-in accounts' hosts; Copilot enterprise hosts; per-domain lists beyond the provider (ADR-0020's
  `domains([…])`).
- Mutation testing (`Scripts/mutate-changed.sh 15a2e19`), run after the commit (`b1291d8`), took about 32 minutes: 80 of 80 killed.
  AskTools had 56 (the tunnel 22, the request 12, the job table 13, the proxy 8, the access 1), AskAgentCore 23 and AskAI 1. The
  `Sources/ask` files have no test target and were skipped.
