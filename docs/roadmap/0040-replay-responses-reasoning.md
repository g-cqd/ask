---
status: in-progress
blocked-by: []
date: 2026-10-19
decision: ADR-0061
---

# 0040 — Replay Responses reasoning

Until this is done a Responses reasoning model starts every tool step without its earlier reasoning (ADR-0033). It
needs a real OpenAI or ChatGPT account, because every claim in it is about what that server accepts:

1. Request `include: ["reasoning.encrypted_content"]`, only for models that accept it (a non-reasoning model refuses it).
2. Record a real stream with sealed content, and check the decoder's stored item against it.
3. Replay the stored item. Probe whether the id may be kept, and what happens when the following item has none: the
   rule pi works around by dropping ids across models.
4. Measure what it buys: tokens and quality on a tool loop with and without it.

## Done (2026-10-22, ADR-0061, diary 2026-10-22-10)

Probed on the live Codex backend: `include` is accepted and not needed; sealed content is verified; ids are optional; replay across
Codex models works; replay cuts reasoning and time where the model reasons and is a no-op where it does not. The Codex dialect now
replays the current tool loop's reasoning and falls back once, with a notice, if the server refuses it.

## Still owed

- A direct OpenAI or ChatGPT API account: `include` may be required, and nothing there is probed (steps 1 and 3 for that server).
- Reasoning older than the latest prompt; long-loop input growth and whether compaction should shed old items.
- Other efforts and models, and the effect on the subscription's usage accounting.
- A second real account's refusal, and a unit test for `CodexProvider`'s gate wiring.
