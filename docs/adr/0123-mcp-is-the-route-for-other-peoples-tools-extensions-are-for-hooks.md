---
status: accepted
date: 2026-10-28
---

# 0123 — MCP is the route for other people's tools; the extension host is for hooks; codemode waits

## Context

Three roadmap entries could each let a third party add to ask: 0067 (MCP client, built), 0033 (ask's own extension host, a
line-delimited JSON-RPC protocol over stdio, with hooks that can block or rewrite a tool call) and 0012 (codemode: the model
writes one script that calls many tools). Their scopes overlap on "add a tool". The owner asked, on 2026-10-28, to go with the
proposal below.

## Decision

- **Tools from outside ask arrive through MCP (0067).** One protocol others already implement; no second tool protocol in ask.
- **The extension host (0033) is kept for hooks only**: the points where something must see or change a tool call or a turn
  (block, rewrite, observe), which MCP cannot express. It adds no tool-registration route of its own.
- **Codemode (0012) is shelved** until real use (0071) shows many-step tool sequences that cost too many round trips.

## Consequences

0033 and 0012 carry a note pointing here; 0033's remaining work shrinks to the hook points. Nothing built changes.
