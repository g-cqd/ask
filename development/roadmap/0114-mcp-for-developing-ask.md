---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0114 — A functional, fast MCP client, and MCP servers for developing ask

Owner wish (2026-10-28 20:04), marked increasingly critical: a functional, high-performance MCP implementation. The owner sees roadmap
items being solved with suboptimal APIs, and says MCP servers such as REA's or apple-docs (`g-cqd/apple-docs`) would help a lot.

The client exists (roadmap 0067: stdio and HTTP transports, config, registry, approval). This item is about making it work well in daily use
and about using such servers.

## Still owed

- Run ask against the apple-docs server from `g-cqd/apple-docs` and record what fails or is slow: connection time, tool listing, call
  latency, large results.
- Budgets for MCP: connection must not delay the first frame (cold start 50 ms); a call's overhead over the server's own time.
- Close the gaps 0067 still lists that daily use hits first (progress in the transcript, resources if apple-docs serves any).
- Decide how the development of ask itself uses these servers, so API choices are checked against current Apple documentation.

## Open questions

- What "REA" refers to: which server, and where it lives.
