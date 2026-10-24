---
status: accepted
date: 2026-10-24
---

# 0080 — Antigravity requests identify as ask, and tool loops need call ids and Gemini 3 signatures

## Context

Roadmap 0052 left three live questions for a signed-in account: whether Cloud Code accepts ask under its own name (pi found the backend
gates its full catalog and model routing on a User-Agent starting `antigravity/cli/`, a first-party identity claim, against ADR-0007's
honest identity), what onboarding and the model list return, and whether the reported rules about thought signatures hold. The owner
signed in (ADR-0075); the probe ran with ask's own credentials against `daily-cloudcode-pa.googleapis.com`, the host the CLI uses, and
printed only statuses, key names, booleans, tier ids, model ids and limits (diary 2026-10-24-26; archived as
`docs/research/probes/AgyCloudProbe.swift.txt`). **No request used the `antigravity/cli/` identity.**

## The probes

All with the User-Agent `ask/0 (Antigravity subscription connector)` and, in the streaming body, the same string in the envelope's own
`userAgent` field.

- **Onboarding accepts ask's identity.** `loadCodeAssist` returns HTTP 200 with a project (a string), `currentTier: free-tier`, `paidTier:
  g1-pro-tier` and no ineligible tiers, with pi's metadata, with metadata minus `ideType`, and with `{}`. **CONFIRMED**: no first-party
  claim is needed to be onboarded.
- **The model list accepts it.** `fetchAvailableModels` returns 200 with 20 entries, a default (`claude-opus-5-5-low`), limits per entry
  (up to 1,000,000 context and 128,000 output) and non-chat entries (`chat_*`, `tab_*`, an image model). Claude Opus 5.5 and Sonnet 5.5 at
  three efforts, Gemini 3 variants, and GPT-OSS 120B are among them. **CONFIRMED.** Whether agy's identity would show more entries was
  **not measured** (that is the claim not made).
- **Streaming works under it** for Gemini 3 Flash, Gemini 3.1 Flash Lite, Claude Sonnet 5.5 and GPT-OSS 120B: HTTP 200, server-sent
  events, `data: ` lines ended with CRLF, each `{"response": {candidates, usageMetadata}, "traceId": …}`; parts are `thought` (text may be
  empty), `text`, and `functionCall {id, name, args}`; a part may carry `thoughtSignature`. **CONFIRMED.**
- **The thought-signature rule holds on Gemini 3.** The call arrives in one part with a 140-character signature. Replayed verbatim: 200.
  Replayed without it: **400 INVALID_ARGUMENT, "Function call is missing a thought_signature in functionCall parts"**. Replayed with the
  documented sentinel `skip_thought_signature_validator`: 200. Reproduced on two models. **CONFIRMED.**
- **Other models need no signature but need the call's id.** Claude and GPT-OSS answered the second round with or without a signature or
  the sentinel, **only** once the `functionResponse` carried the call's `id`; without it: 400 `tool_use_id: Field required` and
  `tool_call_id … populated`. Gemini 3 calls carry an id too and accepted it. **CONFIRMED.**
- **Gemini 2.5 Pro could not be tested**: HTTP 503 "No capacity available for model" on two separate attempts.

## Decision

1. **Every Antigravity request identifies as ask**: the `User-Agent` header and the envelope's `userAgent` field name ask, and the
   onboarding metadata is empty, so no first-party identity is claimed. (ADR-0007's rule holds here.)
2. **Onboarding is `loadCodeAssist`**; its project string rides on every inference request. An account with no project, or an ineligible
   tier, is told to finish onboarding once in `agy`, with the reason codes, and nothing is guessed.
3. **The model list is `fetchAvailableModels`**, read from the account like Codex's (ADR-0037); entries that are not chat models are not
   offered. How to tell them apart (the agent groups, `tieredModelIds`, a per-entry flag) is decided with the parser against fixtures.
4. **A tool result carries the id of the call it answers**, for every model.
5. **On a Gemini 3 or later model**, a replayed function call keeps its real signature when the same provider and model issued it, and
   otherwise carries the sentinel, on the first call of each model turn only, never over a real one. Other models are not changed.
6. **The SSE reader accepts CRLF.** (A first probe parsed nothing: Swift treats `\r\n` as one character.)

## Consequences

- The catalog ask shows may be smaller than agy's. That is unmeasured, and measuring it means sending agy's identity once; it stays a
  question the owner can ask for, not something done silently.
- A 503 "no capacity" is per model and transient; the retry rules treat it like any overloaded provider.
- Not established: where to keep the signature (a marker on the thinking block, ADR-0033, or a field on the call: its own record when the
  encoder is written), the sentinel on later parallel calls, a signature from another model, Gemini 2.x, a signature split across stream
  deltas, and what a refused or expired token looks like on a stream.
