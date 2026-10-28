---
status: accepted
date: 2026-10-19
---

# 0030 — The loop fits the conversation to the window it is shown

## Context

Compaction (ADR-0026) was triggered at 150,000 tokens or by Anthropic's "window full" stop reason. The local server
set up the same day has 32,768 tokens, and an OpenAI-compatible server reports a full window differently: it refuses
the request with a 400, or, llama.cpp, stops a reply mid-way with `length`, the stop reason of the output limit.

## The probes

Ledger in `development/diary/2026-10-19-16.md`. Real bodies from llama.cpp and Ollama; a real 8k llama.cpp server, a task
that must read more than fits, run with and without the window declared, four rounds of probe and fix:

- a refusal for length surfaced as a generic provider failure, and the run ended;
- with the default 80,000-byte kept tail, there was nothing older to summarise;
- the summary request itself (the whole context, as ADR-0026 sends it) overflowed;
- llama.cpp's `length` with 1,143 of 16,384 output tokens was the window filling, and "continue" repeated it;
- `input + cached + output` at that stop was the window exactly: 6,353 + 696 + 1,143 = 8,192;
- four files read in one turn came to 13,451 tokens, which no compaction can split;
- using the model's reasoning as a summary when it wrote none was **refuted**: its musings replaced the goal, and
  the model invented a different task, and exited 0.

After the fixes both runs return the six planted codes, in 123 s declared and 248 s learned.

## Decision

1. A refusal for length is its own kind (`contextOverflow`), recognised from each server's words and codes; it is
   never retried as it was. The loop compacts and sends again **once**; a second refusal ends the run, in words.
2. A reply stopped for length having written less than its allowance is a full window, not an output limit.
3. **The window is learned** from either signal (usage at the stop; `n_ctx` or the refusal's wording) and every later
   request is sized to it, as a declared `contextWindow` in `providers.json` sizes it from the start: reply cap a
   quarter of the window, compaction before reply and margin no longer fit, a kept tail of at most a quarter.
4. A turn's tool outputs share a quarter of a known window, each keeping its head and tail, so a turn always fits.
5. Compaction keeps ADR-0026's cached request first, then falls back to only the replaced part with outputs clipped,
   then, when the model writes no summary, to a mechanical record that keeps the user's words verbatim.
6. A window that fills again after three compactions in a row ends the run instead of looping.

## Consequences

- A local model works without configuration; declaring `contextWindow` makes it about twice as fast (fewer
  compactions, no refusal round-trips).
- The mechanical record is plainer than a model summary but cannot lose the request; a model that answers the
  summary prompt with something else (seen once: "Let me read part3.txt next") is not yet detected.
- `AgentLoop.run` was restructured to stay inside the complexity gate: `WindowWatch` holds the run's window state,
  and streaming moved to its own file.
