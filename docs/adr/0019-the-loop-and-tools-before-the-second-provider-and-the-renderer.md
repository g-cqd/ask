---
status: accepted
date: 2026-10-18
---

# 0019 — The loop and tools come before the second provider and the renderer

## Context

The roadmap ordered: the render pipeline (0013) before the loop (0009), and both providers (0010) before
any tool (0011). After the Claude path landed, ask can stream one reply but cannot act: no turns, no tools,
and no recorded agent history. Reassessing the order found two cycles' worth of drift and two orderings
whose reasons no longer hold:
- 0013 and 0014 blocked each other;
- 0002, 0009 and 0010 named blockers that were done or moot.

## Decision

1. **Tools do not wait for Spettro.** 0010 required both providers first, so that tools would not be built
   against one provider's encoding. That risk is now handled by a seam, not by a second provider:
   - tools consume `(id, name, JSONObject)` and return `(content, isError)` (`RequestBlock.toolCall` and
     `.toolResult`), which no provider owns;
   - OpenAI-completions' `tool_calls` (id, function name, JSON arguments) and `tool` messages
     (`tool_call_id`, content) map onto it field for field.

   Spettro remains owed in 0010. Its adapter must map onto the seam, never widen it.
2. **The loop does not wait for the renderer.** 0009 itself requires the loop to run without a terminal.
   The loop lands headless, driving `ask -p` with tools. The render pipeline (0013) is what the interactive
   screen needs, and it follows.
3. **Order now:**
   1. session payloads for agent turns;
   2. context into requests;
   3. the tool protocol and the first tools;
   4. the headless loop with abort;
   5. the render pipeline and the interactive loop;
   6. re-derive the budgets (0007);
   7. Spettro and the live probes (0010).

## Consequences

- The session format grows the records an agent turn needs: assistant blocks (thinking with its signature,
  tool calls) and tool results. Without them a resumed session could not replay a request exactly.
- 0016's restructure proceeds one target at a time as each one gains content. AskAI was its first step.
