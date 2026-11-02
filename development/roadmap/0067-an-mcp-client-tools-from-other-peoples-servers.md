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
4. **Surface** (done): notices, `/mcp`, the destructive-tool approval of ADR-0111, and progress in the transcript (2026-11-02, below).
5. **Still open** (ordered by value):
   - **Approval of what a server does beyond its tools**, such as a tool the server does not mark destructive but that ask learns is (nothing today can learn that).
   - Resources, prompts, OAuth for remote servers, sampling (refused today).

## Decision (2026-10-28, ADR-0123)

MCP is the route for other people's tools in ask.

## Progress in the transcript (done 2026-11-02)

- `ToolContext.progress` (a `ToolProgressReporter`) and `callID`: the loop runs each call in `context.during(call:)`, and a tool tells
  the run how far it has got with `reportProgress(_:)`. The reporter is `Sendable`, as a server's report arrives on its connection's
  reader, not on the loop's task; the screen's run posts it as `ConversationUpdate.toolProgress(id:text:)`.
- A server's call asks for progress (sends a `progressToken`) only when someone shows it: never in `ask -p`.
- `MCPProgressLine`: the share done when the server gives a total (`25% · reading files`), else its words, else its count; the words on
  one line and cut at 48 characters.
- The line is the block's `BlockProgress.note`, shown on the header's right before its time while the call runs, and dropped when it
  ends; the same line again is no change, so a chatty server redraws nothing new.
- Tests: `ToolProgressTests`, `MCPProgressTests`, `ToolProgressNoteTests`; 14 mutants, all killed (one guard found redundant and
  removed). `Scripts/probe-mcp-progress.py` passes through the release binary and the fixture server (whose `echo` takes `slow`).
- Not done: a report's rate is not limited beyond dropping repeats; resources and prompts (phase 5).
