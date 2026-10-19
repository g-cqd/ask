---
status: not-started
blocked-by: []
date: 2026-10-19
decision: ADR-0033
---

# 0040 — Replay Responses reasoning

Until this is done a Responses reasoning model starts every tool step without its earlier reasoning (ADR-0033). It
needs a real OpenAI or ChatGPT account, because every claim in it is about what that server accepts:

1. Request `include: ["reasoning.encrypted_content"]`, only for models that accept it (a non-reasoning model refuses it).
2. Record a real stream with sealed content, and check the decoder's stored item against it.
3. Replay the stored item. Probe whether the id may be kept, and what happens when the following item has none: the
   rule pi works around by dropping ids across models.
4. Measure what it buys: tokens and quality on a tool loop with and without it.
