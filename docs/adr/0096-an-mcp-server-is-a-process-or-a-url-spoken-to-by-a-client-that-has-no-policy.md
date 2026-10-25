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

## Addendum (2026-10-25): the HTTP transport

Roadmap 0067 phase 2. `HTTPMCPTransport` speaks the streamable HTTP transport over ask's existing `HTTPTransport` and `SSEDecoder`, so it is
tested without a network and adds no dependency.

1. **Every message is its own POST, made at once.** `send` returns before the reply is known, so a tool that takes a minute does not hold
   up the cancel behind it (tested with a held reply and a second request).
2. **Each kind of reply becomes messages.** `application/json` is one message, or each member of a batch; `text/event-stream` is its
   `message` events however the network cut them (other events are ignored); `202` is nothing.
3. **A request that cannot be answered is answered here**, with a made-up error (code -32000) carrying its id and the cause: an HTTP
   error and the start of its body, a reply of another content type, or a reply that ended without the answer to *this* request. The
   caller learns at once instead of at its timeout. A notification has nobody waiting, so a failure of one says nothing.
4. **A session is the header the server sent.** `Mcp-Session-Id` is kept and sent back, `MCP-Protocol-Version` is sent once the handshake
   has agreed one (the connection tells the transport: `negotiated(protocolVersion:)`, a no-op for a pipe), and closing sends `DELETE`
   within a grace and does not mind a `405`. A `404` on a session ends the conversation; opening a new one is the caller's.
5. **A named client.** Every request carries a `User-Agent` the caller names: Apple's documentation server sits behind Cloudflare, which
   refused Python's default with `403` (probe above).
6. **A credential is sent only where ADR-0024 allows it**: `https`, or `http` to this machine. Anything else is refused when the
   transport is made, with a reason that does not repeat the address.

Not done: the optional GET stream on which a server speaks unprompted, so `tools/list_changed` reaches a caller only on a reply stream;
OAuth for a server that asks for it; resuming a dropped stream. Tests: 19 for the transport and one connection over it (80 in the
target, six consecutive green runs). Compiling mutants, all caught: the accept header, the session header not sent, the version header
not sent, a `404` that does not end the conversation, a failure announced for a notification, any event taken for a message, batches not
split, no `DELETE`, the credential policy off, an unanswered event stream (caught by the test's time limit, weaker evidence), and
any response counted as the answer (the first run of it survived; a test was added, then it was caught, also with a time limit).
Against real servers (a throwaway test, not kept, run once each on 2026-10-25): Apple's documentation server over HTTP completed start,
a 9-tool listing and a `search_docs` call in 0.8 s, with ask's own `User-Agent`; `rea` (`bunx rea-agents@6.5.0 mcp`) over stdio completed
start and a 207-tool listing (689 KB of schemas) in 1.5 s and exited 0 on close, leaving no process of its own behind. The Xcode bridge
was not run (it can raise a permission prompt in the owner's session).
