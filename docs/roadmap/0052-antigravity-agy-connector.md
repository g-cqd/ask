---
status: in-progress
blocked-by: []
date: 2026-10-20
---

# 0052 — The Antigravity (agy) connector

Antigravity is installed on the development machine (`/opt/homebrew/bin/agy`) and was on the provider list from the start, but no
roadmap entry, research note or ADR mentions it, so it was only a line in a hand-off. Writing it down here so it is claimable.

What is known, from reading and not from a probe: it needs a Google OAuth PKCE sign-in with a client secret that is discovered
locally, a Cloud Code onboarding step that yields a project and a tier, and a custom streaming protocol that is neither chat
completions nor the Responses API. pi-integrations has a working implementation to read, but the evidence rule applies: run
its code against edge cases, and probe each claim with a real account, before adopting any of it.

Done when: the sign-in and its credential storage follow ADR-0039 (a transaction per save, compare-and-replace for a refresh)
and ADR-0048 (a connection, so several accounts can coexist); the model list, if there is one, is read from the account (ADR-0037);
and a live run through the agent loop is recorded. Probe first whether a connection to it can be made without the locally
discovered client secret, and what that secret's exposure costs.

Probed: **a connection cannot be made without the secret** (the token endpoint refuses the client), and the owner accepts its
exposure (ADR-0073).

## Done (2026-10-23, ADR-0073, diary 2026-10-23-22)

The client secret is found in the user's installed `agy` (1.4.2 and 1.4.6, the same value) and confirmed with Google's token endpoint;
18 deliberate faults killed. `agy` was upgraded from 1.4.2 to 1.4.6 with `agy update` (the old binary is kept in
`~/Library/Caches/ask-mutation/agy/`).

## Done (2026-10-24, ADR-0075, diary 2026-10-24-24)

`ask login agy` and `ask logout agy` exist, for the default account: the authorize URL equals the shipped CLI's, the secret is confirmed
before the URL is shown and kept with the credentials, the paste is validated, and a fake code gets Google's real refusal. 42 faults
killed. **A real sign-in has been done** with the owner's account (userinfo, tokeninfo and a refresh checked; Google does not rotate the
refresh token).

## Done (2026-10-24, ADR-0080, diary 2026-10-24-29)

Probed live with the owner's account and **ask's own identity**: onboarding (`loadCodeAssist`), the model list, and streaming on Gemini 3,
Claude and GPT-OSS all work without the first-party `antigravity/cli/` claim (the open identity question is closed in ask's favour; what it
costs in catalog size is unmeasured). The reported thought-signature rule is **confirmed live** for Gemini 3 (missing: 400; sentinel: 200),
and a tool result must carry the call's id for Claude and GPT-OSS. Nothing is built from this yet.

## Still owed, in order

1. **Access for requests**: refresh when expiring (rediscover the secret on `invalid_client`; a lock is optional since the refresh token is
   not rotated) and named connections (ADR-0048), which come with a provider implementation.
2. **Onboarding** (`loadCodeAssist`: project and tier), the **model list** (`fetchAvailableModels`, ADR-0037), and the **streaming
   protocol** (`streamGenerateContent`), each probed with a signed-in account before any code relies on it.
3. **The client identity.** pi found the backend gates the full model catalog and model routing on a User-Agent starting with
   `antigravity/cli/`. ask identifies itself honestly elsewhere (ADR-0007). First live probe: does an honest identity work, and what
   does it cost in catalog and routing? If it costs something, the owner chooses, and the choice gets its own record.
4. A live run through the agent loop, recorded.

Nothing past the secret is known to work.

## Thought signatures for the inference step (reported 2026-10-24; points 1 and 3 confirmed live, see ADR-0080)

From the pi-integrations fix `704928a` (`src/domains/agy/thought-signature.ts`; tests `test/agy/stream.test.ts`: "Gemini 3 function call
without a usable signature…", "a real signature…", "models that are not Gemini 3…"), read, not run. Each line is a claim to probe with a
signed-in account before the encoder relies on it; none has been tried against the live backend by this project.

1. Gemini 3 and later (`gemini-<N>`, N >= 3) refuse a replayed `functionCall` part with no `thoughtSignature`: HTTP 400 `INVALID_ARGUMENT`,
   "Function call is missing a thought_signature".
2. A signature is kept only when the same provider and model issued it; a foreign history reaches the backend unsigned.
3. For an unsigned call, Google documents the sentinel `skip_thought_signature_validator` (ai.google.dev/gemini-api/docs/thought-signatures):
   only for Gemini 3 or later, only on the **first** function call of each model turn, and never in place of a real signature.
4. In a stream a signature can arrive on any part and may come only on the first delta of a block; a later delta that omits it must keep the
   earlier value.
5. Claude, Gemini 2.x and gpt-oss models get no change.

**Decide before writing the encoder:** `RequestBlock.toolCall` has no place for a signature (only `.thinking(text:signature:)` does; checked in
`Sources/AskAI/Model/RequestBlock.swift`). The option consistent with ADR-0033 is the provenance marker on the thinking block
(`ask-foreign:gemini:{signature}`); that choice needs its own record. Tests first: foreign history gets the sentinel on the first call only; a
same-model signature survives; other models are unchanged; a signature split across stream deltas is retained.

