---
status: accepted
date: 2026-10-24
---

# 0087 — An Antigravity chat model is ask's rule over a list that says no such thing

## Context

Roadmap 0052 needs the account's project (onboarding) and its models before any request can be made. ADR-0080 showed both answer to ask's own
identity and recorded the first shape. What it left open: the model list mixes chat models with others, and the server marks none of them
as chat. This records what was read from a real body (kept outside the repository; a reduced copy is `Tests/Fixtures/Agy/`) and what was
tried against the live account on 2026-10-24, under the identity `ask/0 (Antigravity subscription connector)`.

## The probes

- **Onboarding body.** `loadCodeAssist` returns `cloudaicompanionProject` as a **string**, `currentTier` `free-tier` and `paidTier`
  `g1-pro-tier`, and a list of allowed tiers. **CONFIRMED** for this one account. The shape of the project when it is an object (pi accepts
  one) was **not observed**, so it is refused as unreadable. **Open:** which tier governs quota. The account is a Google AI Pro grant that
  reports `free-tier` as current; both are reported and neither is used.
- **The list's structure.** 20 models in a map, and role lists beside it: `agentModelSorts` (one "Recommended" group of seven ids),
  `commandModelIds`, `tieredModelIds` (three tier names, two distinct ids), `tabModelIds`, `imageGenerationModelIds`,
  `audioTranscriptionModelIds`, and three more that name `gemini-3.5-flash-lite`. **Read.** Fifteen entries are in no agent group (seven
  gemini-2.5 and 3.x ids among them). Two are `isInternal`.
- **Display names are not identifiers.** Four ids (`gemini-2.5-flash`, `-flash-lite`, `-flash-thinking` and `gemini-3.5-flash-lite`) carry the same
  display name, "Gemini 3.5 Flash Lite". Three entries have none. **Read.** So ask lists ids.
- **Every entry against the live stream** (a trivial prompt, one request each, 20 requests). All six Claude entries, `gpt-oss-120b-medium`,
  `gemini-3-flash`, `gemini-3.1-flash-lite`, `gemini-3.5-flash-lite`, `gemini-3.8-flash-tiered` and three of the four `gemini-2.5` ids
  answered 200 with text. `gemini-2.5-pro` answered 503 "No capacity", as it did in the earlier probe. `chat_20706` and `chat_23310` answered
  400. **`tab_flash_lite_preview`, `tab_jump_flash_lite_preview` and `gemini-3.1-flash-image` also answered 200 with text.** So no
  rule of "answers a prompt" separates the models; the rule below is a product choice, and it is conservative.
- **Limits.** Context and output limits are present for every chat entry (1,000,000 and 128,000 for Claude 5.5; 131,072 and 32,768 for GPT-OSS;
  1,048,576 and 65,535 or 65,536 for Gemini). The tab entries report 16,384 and 4,096.

## Decision

1. **The list keeps** the entries that the server's own agent groups, `commandModelIds` or `tieredModelIds` name, plus every entry that reports
   `supportsThinking: true`, and **drops** `isInternal` entries and entries in the tab, image-generation and audio-transcription roles, whichever
   rule would have kept them. Of the live list that is fifteen kept and five dropped.
2. **Order** is the server's: agent groups in order, then command models, then tiered models by tier name, then the rest by id. It does not
   depend on how the server orders the members of an object, and it says nothing about a default.
3. **The default** is the server's `defaultAgentModelId`, reported only when that model is among those kept (ADR-0037: a catalog is observed,
   never guessed). Nothing selects it yet.
4. **Limits** are the server's `maxTokens` and `maxOutputTokens` when they are positive whole numbers; otherwise unknown, never zero.
   `supportsThinking` is carried as reported, or unknown when absent. No reasoning-level list is derived: for Claude the effort is part of the
   id (`-low`, `-medium`, `-high`), and the fields `thinkingBudget`, `minThinkingBudget`, `thinkingLevel` and `supportsAdaptiveThinking` were
   observed but not probed, so they are not read.
5. **Everything from the server is untrusted.** A project id is refused unless it starts alphanumeric, is at most 128 characters and contains only
   letters, digits and `. : - _`; the same check runs before any model request is sent. A tier id is kept only if plain. A Google status word or a
   reason code is repeated only if upper-case letters and underscores, and nothing else of an error body is ever repeated, because the body can carry
   an address or a token.
6. **Identity** is the string above, as probed. The version is 0 because ask has none. Whether the backend would also accept a plainer `ask` is
   unprobed, so the longer form stays.

## Consequences

- A person cannot see `tab_*` or the image model in the list, though both answer. Whether `--model tab_flash_lite_preview` should be refused,
  allowed with a notice, or allowed silently is not decided here, because no provider uses the list yet. **Open.**
- The fifteen are what this account lists today. Another tier or a later server may list others; a new chat model that reports no thinking and is
  in no group would be missed. The rule errs toward leaving something out.
- `gemini-2.5-pro` is listed and has twice answered 503. A catalog says what the account is offered, not what has capacity.
- The Gemini 3 signature rule and the call-id rule (ADR-0080) are still to be built into the stream encoder; this record changes nothing there.
