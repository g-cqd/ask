---
status: not-started
blocked-by:
date: 2026-10-19
decision: ADR-0020
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
