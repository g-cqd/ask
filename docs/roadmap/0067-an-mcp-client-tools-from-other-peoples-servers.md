---
status: in-progress
date: 2026-10-25
---

# 0067 — An MCP client: tools from other people's servers

ADR-0096 holds the decisions. Phases:

1. **Client and stdio transport** (done in this slice): `AskMCP`, tools only, tested against a scripted and a real server.
2. **HTTP transport** (done in the second slice, against a played server; see the ADR's addendum): POST with `application/json` or `text/event-stream` replies, the `Mcp-Session-Id` header when a server sends one,
   a `User-Agent` of ask's own (Cloudflare refused the default one), `DELETE` to end a session (a server may answer `405`).
3. **Integration** (done, ADR-0099): `mcp` in the user's config, a live tool registry, the host and hub, background connection, the sandbox
   rule, `${NAME}` in settings, results as text. A server with more than 16 tools and no `tools` list offers none.
4. **Surface** (done in part): notices and `/mcp`. Not done: progress in the transcript.
5. **Still open** (ordered by value):
   - A **search tool** in front of a large server, so `rea`'s 207 tools are reachable without listing them.
   - **Project-level servers behind trust** (today a project's file may not name one).
   - **Per-call approval** for a tool a server marks destructive (its hints are hints, not facts).
   - The **GET stream** of the HTTP transport, so `tools/list_changed` reaches a caller between requests.
   - A server killed with ask by a signal (the signal exit path does not close servers).
   - Resources, prompts, OAuth for remote servers, sampling (refused today).
