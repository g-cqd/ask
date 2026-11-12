---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0123 — AskMCP covers every specification version and transport, and beats the official SDK

Owner request (2026-10-28 23:15): AskMCP must cover the whole MCP specification in each of its versions, be safer, fully tested, more
efficient and faster at every step than the official Swift SDK (`modelcontextprotocol/swift-sdk`, 0.12.1, targeting 2025-11-25), and
reach servers over streamable HTTP, the older HTTP with SSE, and stdio.

## Where AskMCP stands (2026-10-28)

| Area | AskMCP | Official Swift SDK client |
| --- | --- | --- |
| Versions negotiated | 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05 | 2025-11-25 and earlier |
| stdio | yes, own process group, watchdog (ADR-0102) | yes |
| Streamable HTTP | POST, JSON or SSE replies, batches, session id, `MCP-Protocol-Version`, GET listener, DELETE | yes |
| Resuming a stream (`Last-Event-ID`) | no | to check |
| HTTP with SSE (2024-11-05: GET `/sse`, `endpoint` event, POST there) | no | no client transport |
| Tools, list changes, annotations, structured output | yes | yes |
| Progress, cancellation, ping, logging notices | yes | yes |
| Logging level (`logging/setLevel`) | no | yes |
| Resources (list, templates, read, subscribe) | no | yes |
| Prompts, completions | no | yes |
| Roots, sampling, elicitation (client features) | refused / not declared | yes |
| Authorization (OAuth 2.1, protected resource metadata) | no; headers only | yes (authorization code, private_key_jwt) |
| Tasks, icons (2025-11-25) | no | to check |

Measured already (0114): AskMCP's parsing is at the codec floor for large replies, and HTTP calls are at URLSession's floor. The official
SDK has not been measured.

## Plan

1. **Conformance first, measured by the official suite.** `modelcontextprotocol/conformance` drives a client command through scenarios
   and suites. Build an "everything client" on AskMCP (a small executable beside the benchmarks), run every client scenario, and keep the
   results as the record of what passes, per version.
2. **HTTP with SSE** (2024-11-05) as a third transport, chosen by the configuration or by falling back as the specification describes
   (a POST answered 4xx, then a GET for the `endpoint` event).
3. **Resumable streams**: `id` fields kept, `Last-Event-ID` sent on reconnect, the server's `retry` honoured.
4. **The remaining features**, in the order the suite and real servers need them: resources (apple-docs offers them), logging level,
   prompts, completions, roots, elicitation (through 0117's question tool), sampling (refused by policy today; decide with the owner),
   OAuth for remote servers, tasks and icons.
5. **Faster at every step, shown, not claimed**: add the official SDK's client to `MCPStress` beside AskMCP over the same fake servers,
   for each step (connect, initialize, list, call small and large, cancel), and close any step where it is faster.
6. **Safer**: keep the existing guarantees (unencrypted credentials refused, minimal child environment, group kill, size limits) and add
   fuzzing of the envelope and the SSE parser against malformed input.

## Checked so far

apple-docs' public instance (`https://apple-docs-mcp.everest.mt/mcp`) through the release binary: streamable HTTP with plain JSON
replies, protocol 2025-11-25, stateless; ask offered its nine tools and a `search_docs` call returned real documentation, in 1.5 s for
the whole `ask -p` run. It also offers resources, which ask cannot read yet.

## The conformance suite, step 1 (2026-11-12)

`Conformance/` (a package apart, so ask ships none of it) builds `mcp-conformance-client` on AskMCP: start, list the tools, call the
first, close. `Scripts/mcp-conformance.sh` runs the official suite's client scenarios (`@modelcontextprotocol/conformance` 0.1) against
it, with `Conformance/expected-failures.yml` as the baseline: a run fails on a regression and on a known failure that now passes.

| Scenario | Result |
|---|---|
| `initialize`, `tools_call` | pass |
| `sse-retry` | failed before (no wait, no `Last-Event-ID`, the call failed); passes now: a reply's stream that ends unanswered is resumed after the server's `retry` with `Last-Event-ID`, up to three times |
| `auth/resource-mismatch` | pass |
| `elicitation-sep1034-client-defaults` | fails: elicitation not declared (step 4) |
| the other 21 `auth/*` | fail: the conformance client does not sign in; ask's sign-in (`MCPSignInFlow`, internal to AskTools) needs a headless browser step reachable from this client |

The suite also lists a 2026-07-28 specification version (the Copilot runtime speaks it); AskMCP negotiates up to 2025-11-25.

## Owner's decisions (2026-10-28)

- The plan above is accepted.
- **AskMCP becomes a standalone package, AemiMCP**, in the Aemi family, relying on the other Aemi packages (AemiJSON and the rest) to be as
  fast as possible. ask then depends on it like on the others. Do the conformance and head-to-head work in the new package.
- Investigate `g-cqd/HTTP` if a need arises. It is a from-scratch HTTP/1.1, 2 and 3 *origin server* library (Network.framework,
  epoll on Linux), so it is not a client: its use would be the server side (a conformance server, the fake servers of `MCPStress`, or an
  MCP server of ours), not AemiMCP's requests, which stay on URLSession unless a client is built.
- Sampling is explained to the owner (a server asking the client's model to generate text); the decision is pending.

## Owner's decision on sampling and permissions (2026-10-29)

Be more permissive than refusing everything, and provide granular settings for the MCP scope of each server. Proposed shape, per server
under `mcp.<name>`: `sampling` (`"deny"`, `"ask"` default, `"allow"`) with `samplingMaxTokens`; `roots` (`"none"`, `"workspace"`);
`elicitation` (`"deny"`, `"ask"`); `resources` (`"deny"`, `"read"`); and `tools` allow and deny lists as today. `"ask"` uses the
confirmation picker of 0116 and the approval system of 0134. Typed values only (0118). The conformance suite decides which of these
must exist; the settings come with each feature, not before.
