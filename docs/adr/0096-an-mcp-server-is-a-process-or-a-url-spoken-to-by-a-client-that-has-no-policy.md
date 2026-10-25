---
status: accepted
date: 2026-10-25
---

# 0096 — An MCP server is a process or a URL, spoken to by a client that has no policy

## Context

The Model Context Protocol is how other people's tools reach an agent: the owner's own configuration already names four servers (Xcode's
bridge, Apple's documentation, a reverse-engineering suite, the Agora board). ADR-0028 settled that extensions are processes; ADR-0009
named a leaf for MCP. What was not settled was what the client does and does not decide, and what a server may be trusted with. The
decisions below are the first slice (roadmap 0067); the registry, configuration and sandbox wiring are later slices and are not in it.

## Decision

1. **`AskMCP` is a leaf library**: JSON-RPC over a transport, `initialize`, `tools/list`, `tools/call`, `ping`. It does not know ask's
   registry, sandbox, configuration or UI, and is listed as provider-neutral. Who may run which server, and what a call needs approving,
   are decided by the callers (a later slice).
2. **Tools only.** The client declares no capabilities. A request from the server is refused with `-32601`, except `ping`, which is
   answered. Resources, prompts, sampling, roots and elicitation are not implemented; a server that needs them cannot use them.
3. **Versions.** The client offers `2025-11-25`. It accepts the server's answer if it is `2025-11-25`, `2025-06-18`, `2025-03-26` or
   `2024-11-05`; otherwise it closes the connection and says which version the server named. The reference server answers an unknown
   version with its own latest, which is why the answer, not the offer, is checked.
4. **Schemas and arguments are bytes.** A tool's `inputSchema` is kept as the server wrote it and arguments go out as the model wrote
   them (`JSONObject`), so `$ref`, `$defs`, `oneOf` and `const` reach the model unchanged and nothing is re-encoded.
5. **A server's words are untrusted data.** What is missing is defaulted, what is the wrong shape is skipped (a tool without a name, a
   result that is not an object is a protocol error), and a line that is not a message is reported and does not end the conversation. A
   tool's own failure (`isError`) is a result, not an exception.
6. **Every wait has an end.** Start and each request have timeouts. A cancelled call sends `notifications/cancelled` and stops waiting
   at once: the server may ignore it (the reference server does), so the caller never depends on it. A transport that ends fails every
   waiting call with `disconnected`, and a call made afterwards sends nothing.
7. **A stdio server is third-party code in a child process of its own.** It gets a minimal environment (`PATH`, `HOME`, `USER`, `LOGNAME`,
   `SHELL`, `TERM`, `TMPDIR`, the locale) plus what the configuration names, never ask's own: that environment holds API keys. It leads
   its own session. Closing it ends its input first; after a grace, the polite signal and then the other go to its whole group. A
   message may be at most 64 MiB, and a longer one stops the server. What it writes to standard error is kept, the last 4 KiB, and is
   not part of the conversation.
8. **The client is in-memory testable.** The transport is a protocol; the connection is tested against a scripted server with no process,
   and the stdio transport against a small real one (`Tests/AskMCPTests/Fixtures/fixture-server.py`).

## Consequences

Nothing reaches the model yet: no tool is registered. HTTP is the next slice. A server with many tools is a problem the client does not
solve and the integration must (probes below). The `Mcp-Session-Id`, SSE and `User-Agent` findings below are for that slice.

## Probes (2026-10-25, real servers; scripts were in `/tmp/mcp`, not kept)

| Claim | Result |
|---|---|
| A server answers the version it is asked for | Confirmed for the reference `server-everything` (2025-06-18, 2024-11-05); an unknown version gets its own latest, 2025-11-25 |
| A server honours `notifications/cancelled` | **Refuted**: the reference server ignored it and kept sending progress |
| A server leaves when its input closes | Confirmed for the reference server (0.02 s) |
| Replies arrive in request order | **Refuted**: overlapping requests were answered out of order |
| Startup is fast | **Refuted**: 0.6–3.5 s for the reference server over `npx`, 1.3 s for `rea` |
| Schemas are plain | **Refuted**: `$schema`, `$ref`, `$defs`, `oneOf`, `anyOf`, `const`, `pattern`, `format`, `minimum` all occur |
| A remote server needs a session | **Refuted** for Apple's: JSON replies, no session header, `202` for `initialized`, `405` for `DELETE`; its Cloudflare front returned `403` (error 1010) to Python's default `User-Agent` and `200` to a named one |
| The tool list is small | **Refuted**: `rea` lists 207 tools, about 745 KB of schema and 90 KB of descriptions, on the order of 200k tokens in every request if all were sent |

The last row is the reason registration cannot be "add them all".

## Tests

61 tests in 8 suites: the connection against a scripted server (handshake and versions, paging, content kinds, progress, cancellation,
timeouts, requests from the server, disconnects), the line splitter at every cut, the environment, and the transport against a real
child (a conversation, environment, working directory, standard error, stray lines, pieces, a megabyte, a server that dies, one that
cannot start, one that ignores everything, a message over the limit). Mutants that compile and fail a behaviour check: limit off by one,
empty lines kept, carriage return kept, everything inherited, locale dropped, configured variable does not win, working directory
ignored, ping answered with the wrong id, a too-long message ignored. Two mutants did not compile and were rewritten; one (rescanning
from the start of the buffer) changes cost, not output, and is not caught.

Not covered: that the child is a session leader (the mutant would have signalled the test runner itself, so it proves nothing here), and
that closing reaches a grandchild.
