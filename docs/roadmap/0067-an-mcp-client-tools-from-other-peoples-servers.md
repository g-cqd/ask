---
status: in-progress
date: 2026-10-25
---

# 0067 — An MCP client: tools from other people's servers

ADR-0096 holds the decisions. Phases:

1. **Client and stdio transport** (done in this slice): `AskMCP`, tools only, tested against a scripted and a real server.
2. **HTTP transport**: POST with `application/json` or `text/event-stream` replies, the `Mcp-Session-Id` header when a server sends one,
   a `User-Agent` of ask's own (Cloudflare refused the default one), `DELETE` to end a session (a server may answer `405`).
3. **Integration**: configuration (`[mcp.<name>]`, command or url, env, project-level servers behind the trust prompt of ADR-0035's
   project rules), a registry that can change while a session runs (`tools/list_changed`), names `mcp__<server>__<tool>` (ADR-0092
   keeps these whole), the sandbox policy applied to the child, per-call approval. **Open for the owner**: a server with hundreds of
   tools. Options: an allow-list per server, a deferred "search tools" tool, a cap with a notice. The default must not send 200k tokens.
4. **Surface**: `/mcp` to list servers and their state, progress in the transcript, a notice when a server dies.
5. Later: resources, prompts, OAuth for remote servers, sampling (refused today).
