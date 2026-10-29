---
status: not-started
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
