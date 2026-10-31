---
status: accepted
date: 2026-10-31
---

# 0136 — The provider network level, through a local CONNECT proxy

## Context

The owner (2026-10-31) asked for a network level where commands reach only the model provider's server. ADR-0020's probes stand:
Seatbelt sees IPs and ports, not names, so a profile can allow every host, localhost, or none. Reaching some hosts by name needs a
proxy that reads them (roadmap 0021). Anthropic's sandbox-runtime, behind Claude Code's sandbox, does this: an HTTP CONNECT proxy and
a SOCKS proxy in-process, the proxy variables set for children, and a Seatbelt profile that allows localhost only.

## Decision

- **A level, `provider`,** between `localhost` and `any`. Its Seatbelt profile is `localhost`'s. Commands under it get
  `HTTPS_PROXY`, `HTTP_PROXY` and `ALL_PROXY`, in both cases, pointing at ask's proxy, and an empty `NO_PROXY`.
- **An HTTP CONNECT proxy in ask's process** (`ProviderProxy`, `ProxyTunnel`, `ProxyRequest` in AskTools). It listens on
  127.0.0.1, on a port of its own, and serves `CONNECT host:port` only. A tunnel goes only to an allowed host and port (403
  otherwise), and other methods get 405. Plain HTTP is not served: every provider speaks HTTPS. The proxy resolves names itself,
  so a command needs no DNS.
- **Blocking POSIX sockets, one thread per connection,** not Network.framework or SwiftNIO.
  - A job is started synchronously, so the port must be known when the listener is made, and `getsockname` gives it at once.
    Network.framework reports a port only asynchronously, once its listener is ready.
  - SwiftNIO would be a dependency, with a cost to cold start and idle memory.
  - A model runs a handful of commands at a time, which blocking sockets serve plainly.
- **Nothing runs until a command uses the level** (`ProviderAccess`). The proxy starts on first use; the budgets do not move.
- **The allow list is the run's provider:** `ProviderServer.url(for:environment:)`, which follows `ANTHROPIC_BASE_URL` and a
  configured provider's base URL. Each resolution of the run settings replaces it, `/model` included. It is one host, not every
  signed-in account's: the owner's "the model provider's server".
- **No SOCKS proxy yet.** The variables cover curl, git, Python and Go. A tool that reads none of them fails closed: it reaches
  nothing, since the sandbox allows localhost only.

## Consequences

- Probed live: under `--network provider`, `curl https://api.anthropic.com/v1/models` answers 401 (reached, no key), example.com
  gets the proxy's 403, and `curl --noproxy '*'` cannot resolve the host.
- Certificate pinning is unaffected: the tunnel relays TLS untouched, and the proxy never terminates it.
- Copilot's enterprise hosts and the other signed-in accounts are not in the list. They can be added when a run needs them.
- A tunnel opened before `/model` stays open; new tunnels follow the new list.
