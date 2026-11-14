---
status: in-progress
blocked-by: []
date: 2026-11-13
---

# 0235 — ACP: editors run ask in their agent panel

From the study of other agents (proposal 3), chosen 2026-11-13; after the RPC mode.

`ask --acp` speaks the Agent Client Protocol on stdio, so Zed and the JetBrains IDEs run ask in their agent panel: prompts, streamed
replies and thinking, tool calls, ask's approvals and questions as the editor's permission prompts, sessions listed and resumed.

## Done when

Zed runs ask through ACP for a prompt with a tool call and an approval (checked by the owner), and a probe drives the protocol.

## 2026-11-14

One with roadmap 0234 step 2: `ask serve` is the ACP agent (ADR-0153), not a second front named `--acp`.
