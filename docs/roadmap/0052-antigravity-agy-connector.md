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

## Done (2026-10-24, ADR-0080, diary 2026-10-24-33)

Probed live with the owner's account and **ask's own identity**: onboarding (`loadCodeAssist`), the model list, and streaming on Gemini 3,
Claude and GPT-OSS all work without the first-party `antigravity/cli/` claim (the open identity question is closed in ask's favour; what it
costs in catalog size is unmeasured). The reported thought-signature rule is **confirmed live** for Gemini 3 (missing: 400; sentinel: 200),
and a tool result must carry the call's id for Claude and GPT-OSS. Nothing is built from this yet.

## Done (2026-10-24, ADR-0087, diary 2026-10-24-41)

Onboarding and the model list: `AgyCloudClient.account` (project and tiers) and `.models` (a conservative chat filter over a list that
marks none; the server's default reported when listed), against a fixture reduced from a live body, 34 faults killed. Not wired to
`ask models` or a cache, and no request is streamed yet.

## Done (2026-10-24, ADR-0090, diary 2026-10-24-45)

The stream decoder and the request encoder: a Gemini 3 signature stored in a thinking block of its own, bound to the model, with the sentinel
for the rest; ids on every call and result; the real tool schemas as `parametersJsonSchema`. A live tool loop through both on four models, 81
faults killed. Nothing sends a request through them yet.

## Done (2026-10-25, diary 2026-10-25-14)

The interactive screen with `agy`, run live through a PTY and an emulator (`Scripts/probe-agy-live.py`, opt-in): the label, a tool call, a mid-session switch to Claude and back with a
Gemini signature in the history, an abort and the next turn, and a clean exit. No code changed.

## Done (2026-10-25, ADR-0098, diary 2026-10-25-10)

The model list is cached per project (`models-agy.json`), fetched by `ask models agy` and read by a run, one entry, with no network: a run that
follows it knows its model's window and compacts before the server refuses. Live: `gpt-oss-120b` resolved 131,072 and compaction at 85,197.
11 faults killed.

## Done (2026-10-25, ADR-0101, diary 2026-10-25-13)

`ask --provider agy --model M` runs: the client, access (refresh with one secret search, onboarding stored with the credentials, the
unsaved-rotation notice), `ask models agy`, and the name reserved through settings, sessions and composition. Live through the shipping binary
on three model families, including a refresh, a multi-step Gemini 3 loop and a resumed session. 46 faults killed.

## Still owed

What is known and what is not is registered in `docs/research/antigravity-2026-10.md`, with an id per unknown (`U1`…`U22`). The work that follows from it:

1. **Probe where ask only guesses** (U1, U3, U6, U8, U11): roadmap 0069. The length refusal (U1) waits for the owner's approval of one large request.
2. **A connection kind** (`ask login agy --name`, a second account, the account chooser of roadmap 0046): needs a second Google account (U21).
3. **What a run with no cached list should do**, and whether a model the list does not name should be said before the request (U17, U18).
4. **The owner's decisions**: the first-party identity and what it costs in catalog (U12, ADR-0080), whether the `tab_*` and image models may be chosen (U19), and whether the
   subscription's terms allow this use at all (U22, which no probe can settle).

Not owed any more, and recorded above: access (refresh, secret rediscovery, onboarding stored), the client identity (ADR-0080: ask's own works), the model list, the stream, the
provider, the cached list and the interactive screen.

## Thought signatures for the inference step (reported 2026-10-24; points 1, 2, 3 and 5 confirmed and built, ADR-0080 and ADR-0090; point 4, a signature split across deltas, never observed: U8)

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

**Decided in ADR-0090** (the paragraph below is what was open when it was written): `RequestBlock.toolCall` has no place for a signature (only `.thinking(text:signature:)` does; checked in
`Sources/AskAI/Model/RequestBlock.swift`). The option consistent with ADR-0033 is the provenance marker on the thinking block
(`ask-foreign:gemini:{signature}`); that choice needs its own record. Tests first: foreign history gets the sentinel on the first call only; a
same-model signature survives; other models are unchanged; a signature split across stream deltas is retained.

