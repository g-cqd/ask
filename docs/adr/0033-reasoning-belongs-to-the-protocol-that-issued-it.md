---
status: superseded
superseded-by: ADR-0062
date: 2026-10-19
---

# 0033 — Reasoning belongs to the protocol that issued it

> Superseded by ADR-0062 for the ChatGPT Codex backend: replay was probed live and is now sent inside the tool loop
> (decisions 2, 4 and 5 below). The provenance marker, the Anthropic rule and the decoder's rule still stand; other Responses
> servers still send no reasoning.

## Context

A thinking block carries a `signature`. Anthropic signs its reasoning and refuses a signature it did not issue. The
Responses API (OpenAI, and the ChatGPT subscription's Codex backend) returns reasoning as an item whose
`encrypted_content` must go back whole for the model to keep its train of thought across tool calls. A session can move
between providers, so a block signed by one protocol will meet another's encoder.

## Decision

1. A signature issued by any protocol other than Anthropic's is stored behind a marker (`ReasoningProvenance`) that no
   Anthropic signature can start with, naming the scheme: `ask-foreign:responses:{item json}`. An unmarked signature is
   Anthropic's; an empty one is nobody's.
2. Each encoder sends only what it recognises as its own. Anthropic's drops marked and empty signatures. The Responses
   encoder, for now, sends no reasoning at all.
3. The Responses decoder keeps a reasoning item whole behind the marker, but only when it carries `encrypted_content`.
   A server that sends none (llama.cpp) leaves the block unsigned, so nothing unreplayable is stored.
4. The Responses encoder sends no item `id` and no reasoning, so a server that checks that a reasoning item is
   followed by the item it came with has nothing to check. This is the shape pi uses for a session that moved between
   providers.
5. Replaying reasoning is a second step, owed (roadmap 0040): it needs `include: ["reasoning.encrypted_content"]`, which
   only reasoning models accept, and the pairing rule confirmed against a real account.

## Evidence

Recorded, from Ornith on llama.cpp 0.7.0 (diary 22): the event sequence, `item_id` on every delta and no `output_index`,
usage only in the terminal event, a reply cut at the limit reported `completed`, an empty `encrypted_content`, the
refusal-for-length body. The agent loop ran against it through a tool round trip.

Hand-built from OpenAI's documented shapes, as pi decodes them: summaries and their parts, `response.incomplete`,
`response.failed`, encrypted content. Not recorded: no OpenAI or ChatGPT account has been used. pi's source says OpenAI
validates reasoning/item pairing; that is a reading of source, not a probe.

## Consequences

- A session started on Codex and resumed on Claude, or the reverse, works: foreign reasoning is not sent.
- Until step 5, a Codex or OpenAI reasoning model starts each tool step without its earlier reasoning. It is correct,
  and costs some quality and cache; the size is unmeasured.
- The Anthropic encoder's rule is "not Anthropic's if marked", never "looks like Anthropic's", because no real
  Anthropic signature has been recorded in this repository to say what theirs look like.
