---
status: in-progress
date: 2026-10-25
---

# 0067 — An MCP client: tools from other people's servers

ADR-0096 holds the decisions. Phases:

1. **Client and stdio transport** (done in this slice): `AskMCP`, tools only, tested against a scripted and a real server.
2. **HTTP transport** (done in the second slice, against a played server; see the ADR's addendum): POST with `application/json` or `text/event-stream` replies, the `Mcp-Session-Id` header when a server sends one,
   a `User-Agent` of ask's own (Cloudflare refused the default one), `DELETE` to end a session (a server may answer `405`), and the
   server's own GET stream, which carries what it says unprompted (ADR-0108).
3. **Integration** (done, ADR-0099): `mcp` in the user's config, a live tool registry, the host and hub, background connection, the sandbox
   rule, a watchdog for a killed ask (ADR-0102), project-level servers behind trust (ADR-0103), `${NAME}` in settings, results as text. A server with more than 16 tools and no `tools` list is searched, not listed (ADR-0100).
4. **Surface** (done in part): notices, `/mcp` and the destructive-tool approval of ADR-0111. Not done: progress in the transcript.
5. **Still open** (ordered by value):
   - **Approval of what a server does beyond its tools**, such as a tool the server does not mark destructive but that ask learns is (nothing today can learn that).
   - Resources, prompts, OAuth for remote servers, sampling (refused today).
