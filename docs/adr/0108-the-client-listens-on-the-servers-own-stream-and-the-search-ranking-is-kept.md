---
status: accepted
date: 2026-10-25
---

# 0108 — The client listens on the server's own stream, and the search ranking is kept

Two leftovers of roadmap 0067, each too small for a record of its own.

## 1. The server's own stream (the GET of the streamable HTTP transport)

ADR-0096's HTTP transport carries each message as its own POST and lists what it does not do: the GET stream on which a server sends
messages unprompted, so `tools/list_changed` reaches a caller between requests. **The client now asks for it once, after the handshake**
(the connection's `negotiated`, which already exists for the version header).

1. **The GET carries what the POSTs carry** — the session id, the protocol version, who is asking — and asks for `text/event-stream`
   alone, with no content type.
2. **A server that has none is not a problem.** A 405, or a 200 of another content type, ends the listening quietly; the conversation
   goes on over its POSTs, and the GET is not asked for again. A stream that ends on its own is the same.
3. **What the stream carries is delivered like any reply**: notifications reach the connection's events (a `tools/list_changed` is
   answered by listing again, as ADR-0099 already does), and a response on it resolves the request it answers.
4. **Closing stops listening**, and a negotiation after the close starts no stream.
5. **Not done:** reconnecting with `Last-Event-ID` when a server drops the stream mid-conversation. The stream is an extra ear, not a
   leg: losing it loses nothing the POSTs cannot carry.

## 2. The search ranking is evaluated and kept

ADR-0100's probe said the ranking of `mcp_search` was "not evaluated" and its top match for "decompile function" was "plausible and
not obviously best". It has now been evaluated on the real corpus (`rea`, 207 tools, their names and descriptions) with twelve
realistic asks, each judged against what a person reading the catalog would want:

- **11 of 11 answerable asks put the wanted tool in the top 8** (the twelfth had nothing to find: `rea` has no tool for it). The
  window matters more than the first place: the model reads all eight, with descriptions and schemas, and picks.
- **Top-1 is often noisy** — "decompile this function" ranks `batch_decompile` first and the tool a person means third — because
  common words like "this" match nearly every description. Accepted: the 3:1 name weighting and the eight-wide window absorb it.
- **IDF weighting was tried and rejected**: words weighted by how rarely they appear did not improve the hit count (10/12 on the same
  asks) and regressed one the plain count got right. The plain substring ranking stays.

## Probes and tests

| Claim | Result |
|---|---|
| The GET is asked for after the handshake, with the right headers | `HTTPMCPListenTests` against a played server |
| A 405 is not a failure, and one GET is asked | same |
| What the stream says arrives, and a changed tool list reaches the connection | same |
| A stream that ends on its own is not a failure | same |
| Closing stops listening (the held stream is let go) | same |
| No stream is started after the close | same |
| Ranking on the real corpus | the twelve asks above, run over `rea`'s live tool list |

Compiling mutants, all caught: the listener not kept or not cancelled on close, the GET asking for the wrong kind, the GET sending a
content type. Three were not caught and are recorded rather than hidden: the close-race pair (a check in `listen` that a test cannot
force, because the window is between the negotiation and the send, and the same check in `negotiated`, which the first makes
equivalent) and the content-type check on a 200 reply (a body without SSE `data:` lines delivers nothing either way, so the mutant is
equivalent for anything a server plausibly sends; the check stays as one line of defense).
