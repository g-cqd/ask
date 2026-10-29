---
status: accepted
date: 2026-10-29
---

# 0130 — A searched MCP server keeps two tools, search and call; whether to keep promotion is measured first

## Context

ADR-0100 puts two tools in front of a server with more than 16 tools: `mcp_search` (words, optionally a server) and `mcp_call`
(server, tool, arguments). `mcp_search` also **promotes** what it finds: at most eight matches per server are offered directly as
`mcp__<server>__<tool>` from the next request on (`MCPCatalog.promote`). So a found tool can be called two ways.

The owner asked (2026-10-29) whether the two tools should be one, with an argument that says search or call.

Separately, roadmap 0144 found that Anthropic refuses, on a Claude subscription, any request that offers a tool whose name starts with
`mcp_`. The schema, approval and cache considerations below address whether search and call should be separate tools.

## Decision

1. **Two tools stay; they are not merged into one with an action argument.**
   - *Schema.* Search requires `query`; call requires `server`, `tool` and `arguments`. One tool needs every field optional, or a `oneOf`
     of two shapes, which OpenAI's strict mode and Gemini handle poorly. The provider then cannot enforce what each action requires,
     and models send more malformed calls. Two small tools with their own required fields are what providers validate and models use best.
   - *Risk.* Search reads ask's own catalog; call runs another program's tool outside ask's sandbox. Approval works by tool name
     (ADR-0111 today, roadmap 0134 later); one tool would make every rule read inside the arguments.
   - *Cost.* Merging saves one tool's name and header, a few dozen tokens a request; the two descriptions remain.
2. **Promotion overlaps with call, and one of them should go. Which one is decided by measurement, not now.**
   - *Option A, search and call, no promotion:* the tool list never changes during a session, so the provider's prompt cache, whose first
     block is the tool list, survives every search.
   - *Option B, search and promotion, no call tool:* one tool fewer, but every search that changes the promoted set changes the tool list,
     and the next request rereads the whole conversation without the cache.
   - Preferred, pending the numbers: **A**. The measure, on a real session: input tokens read from cache on the request after a search
     that promotes, against the same search without promotion, on Anthropic and on an OpenAI-compatible provider; and how often models
     call a promoted tool against `mcp_call` in the probes' transcripts.

## Consequences

- No change to `MCPSearchTool` or `MCPCallTool` from this decision; their names stay until a reason of their own changes them.
- The promotion measurement is owed. The roadmap entry that takes it up (0114, daily use of MCP) records the numbers, and the
  choice between A and B amends this ADR.
- If A is chosen: `MCPCatalog.promote` and the `/promoted` publication go, `mcp_search`'s description stops saying matches become
  callable, and the probes of ADR-0100 and ADR-0108 are updated.
