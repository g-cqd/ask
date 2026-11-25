---
status: accepted
date: 2026-11-14
---

# 0153 — `ask serve` speaks ACP, and a served session is the conversation the screen drives

## Context

Roadmap 0234 step 2 asked for a JSON-RPC mode for a long-lived driver, and 0235 for ACP on top of it, so editors run ask in their
agent panel. Put to the owner (2026-11-14) with what the ACP v1 specification says, read that day (overview, prompt turn, tool
calls, session setup, elicitation, extensibility at agentclientprotocol.com/protocol/v1):

- ACP is JSON-RPC 2.0 with the shape serve needed anyway: `initialize`, `session/new`, `session/load`, `session/prompt`,
  `session/cancel`; `session/update` notifications; `session/request_permission`; `elicitation/create`.
- Its updates have words for nearly everything a conversation says: message and thought chunks, tool calls, notices, compactions,
  usage, the session's title, the commands available.
- It can be extended without breaking a peer: methods whose name starts with `_`, and `_meta` fields.

The owner chose: **ACP is serve's protocol** (one, not two), **a served session is the whole conversation** (commands, goals,
loops, threads, steering), and **the Aemi family's code is used wherever it exists**, probed for first
(`development/research/serve-inventory-2026-11-14.md`).

## Decision

The owner's, 2026-11-14:

1. **One protocol.** `ask serve` speaks ACP v1. There is no protocol of ask's own beside it; what ACP has no word for uses ACP's
   own extension points, or is not sent.
2. **A served session is the conversation the screen drives**, not the bare loop `ask -p` runs: slash commands, goals, loops,
   threads and steering are the conversation's, so they are a served session's.
3. **The family's code first.** Before anything is implemented, what exists in the Aemi family and in ask is probed for and used.
   The first result: the wire is AemiJSONRPC's (`JSONRPCConnection`, line framing, a descriptor reader), which ask's pinned
   AemiJSON already carries. ask writes no JSON-RPC for serve.

## Consequences

- Roadmap 0234 step 2 and 0235 are one piece of work with one probe. `--json` stays as it is for one-shot runs.
- serve's shape follows ACP's versions; `initialize` negotiates the version.
- Several sessions in one process, each with the `cwd` it was created with, is what ACP's clients expect. The conversation reads
  the process's working directory in eleven places in `AskSession` today; each has to take the session's.
- A correction to what the owner was told when choosing: the conversation's updates are AskTUI's types, and a front in or above
  `AskSession` can consume them where they are, since `AskSession` already imports AskTUI. Moving them below the screen's library
  (plan B's leftover) is not needed for serve.
- ask's MCP client has a JSON-RPC of its own although AemiJSONRPC existed. That is not changed by this record; it is the first
  finding of the audit of in-house reuse.

## Not decided here

The design that follows from these three (the target it lives in, how each of the conversation's updates maps, approvals,
secrets, the order of work, and five open points) is proposed in `development/research/serve-design-2026-11-14.md` and waits for
the owner's reading. Nothing is built.

## Probes

`development/research/serve-inventory-2026-11-14.md` and diary 2026-11-14-08.
