---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0121 — Investigate an event-driven architecture for every exchange

Owner wish (2026-10-28 22:40): investigate an event-driven architecture to speed up all exchanges, inside ask and with the outside.

## Still owed (investigation)

- Map today's exchanges and how each waits: the agent loop and the screen (AsyncStreams, the render thread), tools and jobs, MCP
  (0114 measured its hand-offs: about 4 µs a call on loopback, 15 µs on stdio, all scheduling), providers over HTTP and SSE.
- Find where polling or extra hops remain (for example the job output watcher's 100 ms coalescing sleep) and what an event would replace.
- Measure before proposing: the cold start, input and action budgets are the bar.
