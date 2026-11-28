---
status: accepted
date: 2026-11-28
---

# 0171 — The MCP client lives in AemiMCP

## Context

Six packages of the family spoke the Model Context Protocol with code of their own: ask as a client (`AskMCP`, ADR-0096,
with the HTTP transport and OAuth sign-in), and swift-search, litmus, apple-docs, VMRunner and sunset as servers. They
diverged in protocol versions, cancellation and validation. The owner asked for one package, `g-cqd/AemiMCP`, on Aemi
and AemiJSON, and for every consumer to move to it.

## Decision

1. The client (`MCPConnection`, the stdio and Streamable HTTP transports, OAuth discovery and sign-in) moved to AemiMCP
   unchanged in behaviour, with the 114 tests `Tests/AskMCPTests` kept for it. ask depends on AemiMCP without its `HTTP`
   trait, so the HTTP server responder and `g-cqd/HTTP` stay out of ask's graph.
2. `AskMCP` stays a library, now the glue between ask's seams and AemiMCP's: `MCPHTTPBridge` makes an `HTTPTransport`
   (`URLSessionTransport`, `PinnedPublicTransport`, a test's stand-in) AemiMCP's `MCPHTTPClient`, and `JSONObject` and
   `MCPJSONObject` convert both ways. AemiMCP has no dependency on ask; ask's policy (which servers, approvals, the
   inward-address and plain-HTTP refusals before a credential is sent) stays in `AskTools`, as ADR-0096 decided.
3. AemiMCP's names carry its prefix where ask's AskAI types had the same role: `MCPHTTPRequest`, `MCPHTTPResponse`,
   `MCPJSONObject`, `MCPPKCE`, `MCPEndpointPolicy`, `MCPSSEDecoder`. AskAI keeps its own (`PKCE` for the Claude sign-in,
   `EndpointPolicy`, `InwardAddress`).

## Consequences

- A protocol fix lands once, in AemiMCP, and reaches ask with a repin.
- A tool call's arguments are validated once more on their way to AemiMCP (one parse of the arguments per call); a
  server's input schema once per listing on its way to the model.
- The fixture servers stay in `Tests/AskMCPTests/Fixtures`, where ask's probe scripts read them; AemiMCP keeps a copy for
  its tests.
- The conformance client (`Conformance/`) is built on AemiMCP through the same bridge.
