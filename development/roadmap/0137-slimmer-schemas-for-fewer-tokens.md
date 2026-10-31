---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0137 — Investigate slimmer JSON schemas to cut the tokens of each turn

Owner wish (2026-10-29 00:35): investigate ways to slim down the JSON object schemas that models must answer with, and the ones ask sends
too, to cut the tokens used at each turn.

## Still owed (investigation)

- Measure: how many tokens the tool definitions cost per request today (ask's own tools, MCP tools, skills), per provider's tokenizer
  or the provider's own count.
- Candidates: shorter descriptions, dropping optional parameters the model never uses, sending `$defs` once, enum values in place of
  prose, loading tool definitions on demand (as the search tool for large MCP servers already does, ADR-0100), and for providers that
  cache a prefix, keeping the tool block byte-identical between turns.
- The reverse direction: structured outputs the model must write (tool arguments) with shorter key names where a provider accepts them.
- Never at the price of the model calling a tool wrongly; measure the call success on the scripted suite before and after.

## Measured (2026-10-31)

`Scripts/measure-request-size.py` captures the first request of `ask -p hi` through a fake provider and reports compact bytes per part
and per tool, and properties repeated across tools (`--mcp-from CONFIG` copies only a config's `mcp` section). Guards:
`RequestSizeTests` in `test-measurements.py`, red first. Report: `development/research/tool-definition-sizes-2026-10-31.md`.

- ask's own six tools: 5.0 KB (about 1,700 tokens, estimated at three bytes a token). The per-call `sandbox` parameter repeats in four
  of them, 1.1 KB beyond one copy.
- With the owner's MCP servers: 23.5 KB of tools, 17.6 KB of it MCP: apple-docs and swift-search have 9 tools each, under the
  16-per-server limit, so all are sent in full.
- The tool block is byte-identical between turns and cached on Anthropic, so the cost is mostly context window and uncached providers.

## For the owner

1. A budget for direct MCP tools across all servers, by count or by bytes, past which servers go behind `search_catalog`
   (saves up to ~15 KB a request with today's servers).
2. Whether `read` and `write` keep the per-call `sandbox` parameter, or only `bash` does (about 1.1 KB).

Not taken: dropping MCP's `$schema` (server schemas are carried byte for byte by design, and `$schema` governs `$ref`), and the
enum list in the sandbox description (about 180 bytes; it goes with choice 2). Not verified: token counts (no provider was asked) and call success after a cut (needs a real model).

