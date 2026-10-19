---
status: accepted
date: 2026-10-19
---

# 0028 — Extensions are processes; hooks are in the loop

## Context

pi is extended by TypeScript modules loaded into its process. They register tools, commands, providers and MCP
servers, and attach to named lifecycle events, each with a declared effect: `tool_call` may block or rewrite,
`tool_result` composes, `context` transforms, `provider_stream_event` observes. `ask` is a compiled Swift binary
with a 25 ms cold-start budget and a decided sandbox model (ADR-0020: `ask` supervises, children are sandboxed).
It cannot load TypeScript, and loading anything into its own process defeats the sandbox.

## The probes

- **Hooks in the loop.** `AgentHook` lets code block, rewrite or transform each tool call; tests pin order (a
  rewrite reaches the next hook, the first block wins, transforms compose), and each rule was broken once.
- **IPC is not the cost.** A Swift parent sending a JSON-RPC-shaped hook to a child over pipes measured 0.009 to
  0.015 ms p50 and 0.03 ms p99 round trip, for a Python child and a compiled one alike. The probe was checked
  against a child that sleeps 1 ms, which it reported as 1.29 ms. A hook on every tool call is free beside the
  tool (spawning bash alone is about 2.5 ms).
- **Spawning is the cost.** A Python extension took 25 to 53 ms to start and answer, a compiled one 5 ms: up to
  twice the whole cold-start budget.

## Decision

1. **Three tiers, smallest first.** Configuration (`providers.json`, ADR-0027) needs no code. Hooks are the
   in-process seam (`AgentHook`), used by ask's own features: approval, sandbox policy. Third-party code runs as
   an **extension process**.
2. **An extension is an executable** speaking line-delimited JSON-RPC 2.0 over stdin and stdout, in any language.
   At start it declares tools and the hooks it wants; `ask` routes tool calls and hook events to it. One protocol
   covers what pi's events cover, beginning with `tool_call`, `tool_result` and agent-event notifications.
3. **Extensions never delay the first frame.** They start after it, in parallel; a tool an extension provides is
   available once that extension answers.
4. **Each extension is a sandboxed child**, under the intersection of the layers ADR-0020 defines, so an extension
   cannot do what the user did not allow ask to do.
5. **MCP servers use the same transport** (JSON-RPC over stdio) and arrive as a client on the same plumbing.
6. **In-process JavaScript (JavaScriptCore) is reserved for the codemode host** (roadmap 0012), not extensions.

## Consequences

- Extensions are crash-isolated and language-agnostic, and a pi TypeScript extension could be bridged by a small
  shim rather than reimplemented.
- The protocol is a public contract and is versioned from its first release.
- Owed (roadmap 0033): the host, the protocol document, a reference extension, and the sandbox wiring. Roadmap
  0027 keeps the registry work: tools that appear mid-session, and tool annotations (read-only, destructive).
